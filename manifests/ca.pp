# installs a CA client certificate for openldap and rehashes certdir
# slightly outside the scope of this module but useful utility
# must define only one of the following:
# ca_cert_path can be a local filesystem path or puppet URI
# ca_cert_contents can be a string

define ds389::ca (
    $ca_cert_path = undef,
    $ca_cert_contents = undef,
    $cacertdir = '/etc/openldap/cacerts',
    $ca_name = "$name",
) {

  file { "${cacertdir}": 
    ensure => directory
  } ->

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
