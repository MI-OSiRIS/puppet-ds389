class ds389 (
	$ensure = present,
	$snmp = false,
) {

	if $ensure == present {
		$service_enable = true
		$service_running = true
	} else {
		$service_enable = false
		$service_running = false
	}

	if $snmp == true {
		$snmp_service_enable = true
		$snmp_service_running = true
	} else {
		$snmp_service_enable = false
		$snmp_service_running = false
	}

	package { ['389-ds-base', '389-ds-base-libs', '389-ds-base-snmp', '389-admin-console', '389-ds-console']:
    	ensure => $ensure,
  	} -> 
  	
  	service { 'dirsrv-snmp': 
  		ensure => $snmp_service_running,
  		enable => $snmp_service_enable
  	}

  	$ldapmodify         = '/usr/bin/ldapmodify'
}
