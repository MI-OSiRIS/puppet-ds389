# this doesn't really behave right when the ldif param is used to provide inline ldif - there's no file change to trigger re-run of the exec
# the force_update param is a hack to force re-run of the ldapmodify command in this case

define ds389::ldif (
	$instance,
	$template_path = 'ds389/ldif',
	$root_dn_pass,
	$root_dn,
	$ldif_file     = "${name}",  # not fed to ldapmodify if $ldif text is provided directly, but still used as unique identifier 
	$ldif          = undef,
	$force_update  = false,
	$template_vars = undef
) {

	$database    = "/etc/dirsrv/slapd-${instance}"
	$ldapmodify  = $::ds389::ldapmodify

	if $force_update {
		file { "$instance-$ldif_file":
      		path    => "${database}/${ldif_file}",
      		ensure  => absent,
      		before  => Exec["ldapmodify-${instance}-${ldif_file}"]
      	}
	}

	if ($ldif) {
		$command = "/bin/echo \"${ldif}\""
	} else {
		$command = "/bin/cat ${database}/${ldif_file}"

		file { "$instance-$ldif_file":
      		path    => "${database}/${ldif_file}",
      		content => template("${template_path}/${ldif_file}.erb"),
      		tag     => 'ds389-ldif',
      		notify  => Exec["ldapmodify-${instance}-${ldif_file}"]
      	}
	}
    
    exec { "ldapmodify-${instance}-${ldif_file}" :
      command => "${command} | ${ldapmodify} -v -x -D \"${root_dn}\" -w ${root_dn_pass} ; if [ $? -eq 0 ]; then touch ${database}/${ldif_file}.done; fi",
      creates => "${database}/${ldif_file}.done"
    } 
}