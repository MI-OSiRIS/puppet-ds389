# Somewhat copied from ds_389 module by jlcox1970: https://github.com/jlcox1970/ds_389
#


define ds389::site (
  $suite_spot_group      = 'dirsrv',  # RHEL7 default
  $suite_spot_user_id    = 'dirsrv',
  $root_dn               = 'cn=Directory Manager',
  $instance_hostname     = $::fqdn,
  $root_dn_pass          = $root_dn_pass,
  $suffix                = 'dc=example,dc=com',
  $instance              = $name,
  $server_port           = '389',
  $server_ssl_port       = '636',
  $certfile              = undef, # path to p12 keycert to import
  $certname              = 'Server-Cert', # certificate identifier - looks for this to determine if cert should be imported or already exists
  $certpass              = '', # PKCS12 keycert pass 
  $kspass                = '', # Keystore pass 
  $cafile                = undef, # path to ca cert to import with keycert
  $caname                = 'CA1', # identifier to use for imported CA.  No spaces, space and everything after is ignored.
  $ldif_install          = [ 'ssl.ldif' ], # ldif files applied with ldapmodify from $ldif_src/filename.ldif.erb
  $schema_install        = [ 'osiris.ldif' ], # ldif schema extensions from $schema_src/name.ldif - not templated
  $ldif_src              = 'ds389/ldif',  # if over-ridden must contain all templates specified in ldif_install
  $schema_src            = 'ds389/schema', # if over-ridden must contain all files specified in schema_install
  $supplier_bind_dn_pass = undef, # if left undef a supplier bind dn is not created
  $supplier_bind_dn      = 'cn=replication manager, cn=config', 
  $supplier_bind_cn      = 'replication manager', # should match cn for supplier_bind_dn
  $replica_id            = undef, # ID unique to all suppliers between 1 65536
  $replicas              = [], # replica hostnames not including this host.  If empty then no replication agreements are configured.
  $replica_init          = false # if true, init the replica when creating replication agreement. Only one replica should have it true, and it should be the last one configured.
){

  $database           = "/etc/dirsrv/slapd-${instance}"
  $stop               = "/bin/systemctl stop dirsrv@${instance}"
  $start              = "/bin/systemctl start dirsrv@${instance}"
  $ldapmodify         = '/usr/bin/ldapmodify'
  
  unless $root_dn_pass {
    fail ("Directory Service 389 : rootDNPwd : No Password for RootDN :::${root_dn_pass}:::")
  }

  # add backslash before = and ,
  # three \\\ required to escape \ 
  $escaped_suffix = regsubst($suffix, ',|=', '\\\\\0', 'G')

  # values other than start are ignored
  if $replica_init { $start_replica = 'start' } 
  else { $start_replica = 'no' }

  anchor {"${instance} ds389::site::start": } ->

  exec { "${instance} setup ds":
    # the second version also configures an admin server on 9830.  Could be useful to have available.  
    # command => "/usr/sbin/setup-ds.pl --silent General.FullMachineName=${instance_hostname} General.SuiteSpotGroup=${suite_spot_group} General.SuiteSpotUserID=${suite_spot_user_id} slapd.InstallLdifFile=suggest slapd.RootDN=\"${root_dn}\" slapd.RootDNPwd=\"${root_dn_pass}\" slapd.ServerIdentifier=${instance} slapd.AddOrgEntries=yes slapd.ServerPort=${server_port} slapd.Suffix=${suffix}",    
    command => "/usr/sbin/setup-ds-admin.pl --silent General.FullMachineName=${instance_hostname} General.SuiteSpotGroup=${suite_spot_group} General.SuiteSpotUserID=${suite_spot_user_id} slapd.InstallLdifFile=suggest slapd.RootDN=\"${root_dn}\" slapd.RootDNPwd=\"${root_dn_pass}\" slapd.SlapdConfigForMC=yes slapd.ServerIdentifier=${instance} slapd.AddOrgEntries=yes slapd.ServerPort=${server_port} slapd.Suffix=${suffix} admin.SysUser=${suite_spot_user_id} General.ConfigDirectoryAdminID=admin General.ConfigDirectoryAdminPwd=\"${root_dn_pass}\" admin.ServerAdminID=admin admin.ServerAdminPwd=\"${root_dn_pass}\" admin.ServerIpAddress=${net::backend::ip} admin.Port=9830 General.ConfigDirectoryLdapURL=\"ldap://${instance_hostname}:${server_port}/o=NetscapeRoot\"",    
    require => [ Package['389-ds-base'] ],
    creates  => "${database}",
    logoutput => false
  } ->

  # required if the NSS database has a password to access
  #exec { "${instance} setup token":
  #  command => "${stop} ;/bin/echo \"Internal (Software) Token:${root_dn_pass}\" > ${database}/pin.txt ;chown -R ${suite_spot_user_id}:${suite_spot_group} ${database}*  ;${start}",
  #  creates  => "${database}/pin.txt",
  #} ->

  # -W is the PKCS12 password, -K is keystore password.    
  # if we don't stop the instance before doing this the import ends up corrupted and doesn't work
  exec { "${instance} import key and certificate":
    command => "${stop} ; /bin/pk12util -i $certfile -d ${database} -W \"$certpass\" -K \"$kspass\" ",
    unless  => [ "/bin/certutil -L -d ${database} | /bin/grep -q \"${certname}\"", "/usr/bin/test ! -f $certfile" ],
    logoutput => false
  } -> 

  exec { "${instance} import CA chain":
    command => "/bin/certutil -d ${database} -A -n $caname -t CT,, -a -i $cafile; ${start}",
    unless  => [ "/bin/certutil -d ${database} -L | /bin/grep -q \"${caname}\"" , "/usr/bin/test ! -f $cafile" ],
    # logoutput => true
  } ->

  file { "${instance} add CA cert to openldap":
    path => "/etc/openldap/cacerts/${instance}-ca.pem",
    source => $cafile,
    require => File['/etc/openldap/cacerts']
  } ~>

  exec { "${instance} rehash certs":
    command => '/sbin/cacertdir_rehash /etc/openldap/cacerts',
    refreshonly => true
  } ->
  
  service { "dirsrv@${instance}":
      ensure => $ds389::service_running,
      enable => $ds389::service_enable
  } ->

  anchor { "${instance} ds389::site::end": }

###### add a tag to these so you can group the dependencies with a collector, duh!  And do it to the stuff above as well!

  $ldif_install.each | $ldif | {
    file { "$instance $ldif":
      require => Exec["${instance} import CA chain"],
      path => "${database}/${ldif}",
      content => template("$ldif_src/${ldif}.erb")
    } ~>
    exec { "${instance} ldif import ${ldif}" :
      command => "/bin/cat ${database}/${ldif} |${ldapmodify} -v -x -D \"${root_dn}\" -w ${root_dn_pass} ; if [ $? -eq 0 ]; then touch ${database}/${ldif}.done; fi",
      creates => "${database}/${ldif}.done",
      notify  => Service["dirsrv@${instance}"],
      logoutput => false
    }
  }

  $schema_install.each | $schema | {

    exec { "${instance}-stop-install-${schema}":
      command => "${stop}", 
      creates => "${database}/schema/${schema}",
      require => Service["dirsrv@${instance}"] 
    } ->

    file { "$instance $schema":
      notify => Service["dirsrv@${instance}"],
      path => "${database}/schema/99${schema}",
      content => file("$schema_src/$schema")

    } ~>

    exec { "${instance}-start-install-${schema}":
      command => "${start}",
      refreshonly => true
    }

  }
    # doing these inline because passwords are involved that I don't want to save to a file on the system

  if $supplier_bind_dn_pass {

      $repl_bind_ldif = @("EOT")
      dn: cn=replication manager,cn=config
      changetype: add
      objectClass: inetorgperson
      objectClass: person
      objectClass: top
      cn: replication manager
      sn: RM
      userPassword: ${supplier_bind_dn_pass}
      passwordExpirationTime: 20380119031407Z
      nsIdleTimeout: 0
      |-EOT

      exec { "${instance} supplier bind DN" :
        command => "/bin/echo \"${repl_bind_ldif}\" | ${ldapmodify} -v -x -D \"${root_dn}\" -w ${root_dn_pass} ; if [ $? -eq 0 ]; then touch ${database}/supplier_bind_dn.done; fi",
        creates => "${database}/supplier_bind_dn.done",
        notify  => Service["dirsrv@${instance}"],
        require => Exec["${instance} setup ds"],
        logoutput => false
    }

     # generate replication agreements 

    $replicas.each | $replica | {
      $repl_ldif = @("EOT")
      dn: cn=ReplicaAgreement_${replica},cn=replica,cn=${escaped_suffix},cn=mapping tree,cn=config
      changetype: add
      objectclass: top
      objectclass: nsds5ReplicationAgreement
      cn: ReplicaAgreement_${replica}
      nsds5replicahost: ${replica}
      nsds5replicaport: 389
      nsds5ReplicaBindDN: cn=replication manager,cn=config
      nsds5replicabindmethod: SIMPLE
      nsds5ReplicaTransportInfo: TLS
      nsds5replicaroot: $suffix
      description: agreement between $::fqdn and $replica
      nsds5replicatedattributelist: (objectclass=*) $ EXCLUDE authorityRevocationList accountUnlockTime memberof
      nsDS5ReplicatedAttributeListTotal: (objectclass=*) $ EXCLUDE accountUnlockTime
      nsds5replicacredentials: ${supplier_bind_dn_pass}
      nsds5BeginReplicaRefresh: ${start_replica}
      |-EOT

      exec { "${instance} $replica replica agreement" :
        command => "/bin/echo \"${repl_ldif}\" | ${ldapmodify} -v -x -D \"${root_dn}\" -w ${root_dn_pass} ; if [ $? -eq 0 ]; then touch ${database}/repl_agr_${replica}.done; fi",
        creates => "${database}/repl_agr_${replica}.done",
        notify  => Service["dirsrv@${instance}"],
        require => [ Exec["${instance} setup ds"], Exec["${instance} ldif import replication.ldif"] ],
        logoutput => false
      }
    }
  }
}

  # some handy queries

  #info about replication agreements
  # ldapsearch -x -b "cn=mapping tree,cn=config" -D "cn=Directory Manager" -W objectClass=nsDS5ReplicationAgreement -LL                

  # starting replication
  # dn: cn=ExampleAgreement,cn=replica,cn=dc\=osris\,dc\=org,cn=mapping tree,cn=config
  # changetype: modify
  # replace: nsds5BeginReplicaRefresh
  # nsds5BeginReplicaRefresh: start

