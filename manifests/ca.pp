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

  # cacertdir_rehash (authconfig) only exists on EL7 and older; EL8+ have
  # OpenSSL >= 1.1, whose "openssl rehash" builds the same hash links.
  exec { "$ca_name - rehash openldap CA certs":
    command => "/bin/sh -c 'if [ -x /usr/sbin/cacertdir_rehash ]; then /usr/sbin/cacertdir_rehash ${cacertdir}; else /usr/bin/openssl rehash ${cacertdir}; fi'",
    refreshonly => true
  }
}
