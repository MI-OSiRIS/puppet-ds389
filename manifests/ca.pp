# installs a CA certificate
# must define only one of the following:
# ca_cert_path can be a local filesystem path or puppet URI
# ca_cert_contents can be a string

define ds389::ca (
    $ca_cert_path = undef,
    $ca_cert_contents = undef,
    $ca_name = "$name",
) {

  $cacertdir = $ds389::client::openldap_cacertdir

  file { "$ca_name - add CA cert to openldap":
    path => "${cacertdir}/${ca_name}-ca.pem",
    source => $ca_cert_path,
    content => $ca_cert_contents,
    require => File["$cacertdir"]
  } ~>

  exec { "$ca_name - rehash openldap CA certs":
    command => "/usr/sbin/cacertdir_rehash $cacertdir",
    refreshonly => true
  }
}
