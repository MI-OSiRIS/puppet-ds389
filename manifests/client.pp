define ds389::client (
	$ca_cert_path,
	$ca_name = "$name",
	$manage_openldap = true
) {

	if $manage_openldap {
		package { 'openldap':
			ensure => present,
			before => File['/etc/openldap/cacerts']
		}
	}

	if ! defined(File['/etc/openldap/cacerts']) {
		file { '/etc/openldap/cacerts':
  			ensure => directory
  		}
  	}

  	file { "$ca_name - add CA cert to openldap":
    	path => "/etc/openldap/cacerts/${ca_name}-ca.pem",
    	source => $ca_cert_path,
    	require => File['/etc/openldap/cacerts']
  	} ~>

  	exec { "$ca_name - rehash openldap CA certs":
    	command => '/usr/sbin/cacertdir_rehash /etc/openldap/cacerts',
    	refreshonly => true
  	}
}

