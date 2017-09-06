# installs and configures openldap client packages
# use ds389::ca to define CA certificates

class ds389::client (
  $openldap_cacertdir = '/etc/openldap/cacerts',
) {

	package { 'openldap':
		ensure => present,
		before => File["$openldap_cacertdir"]
	}

  package { 'openldap-clients': ensure => present }

  file_line { 'tls_cacertdir':
    path => '/etc/openldap/ldap.conf',
    line => "TLS_CACERTDIR   $openldap_cacertdir",
    match => '^TLS_CACERTDIR.*',
  }

	file { "$openldap_cacertdir":
  	ensure => directory
  }

}

