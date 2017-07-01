# Originally parts of this were copied from ds_389 module by jlcox1970: https://github.com/jlcox1970/ds_389
# This module is targeted at RHEL7 and makes no provision for potential differences of other distributions


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
  $enable_ssl            = true,
  $enable_replication    = false,
  $enable_admin_console  = false,   # init with setup-ds-admin.pl to configure admin console
  $schema_install        = [ 'eduorg.ldif' ], # array of ldif schema extensions to install from those included with module
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
  $ldapmodify         = $::ds389::ldapmodify
  
  unless $root_dn_pass {
    fail ("Directory Service 389 : rootDNPwd : No Password for RootDN :::${root_dn_pass}:::")
  }

  if $enable_replication and ($replica_id == undef) {
    fail ("Enabling replication requires defining a unique replica ID for this instance between 1 and 65536")
  }

  # add backslash before = and ,
  # three \\\ required to escape \ 
  $escaped_suffix = regsubst($suffix, ',|=', '\\\\\0', 'G')

  # values other than start are ignored
  if $replica_init { $start_replica = 'start' } 
  else { $start_replica = 'no' }

  $common_args = "--silent General.FullMachineName=${instance_hostname} General.SuiteSpotGroup=${suite_spot_group} \
General.SuiteSpotUserID=${suite_spot_user_id} slapd.InstallLdifFile=none slapd.RootDN=\"${root_dn}\" \
slapd.RootDNPwd=\"${root_dn_pass}\" slapd.ServerIdentifier=${instance} slapd.AddOrgEntries=no \
slapd.ServerPort=${server_port} slapd.Suffix=${suffix}"    


  if ($admin_server) {

    $admin_args = "slapd.SlapdConfigForMC=yes admin.SysUser=${suite_spot_user_id} General.ConfigDirectoryAdminID=admin \
General.ConfigDirectoryAdminPwd=\"${root_dn_pass}\" admin.ServerAdminID=admin admin.ServerAdminPwd=\"${root_dn_pass}\" \
admin.ServerIpAddress=${net::backend::ip} admin.Port=9830 \
General.ConfigDirectoryLdapURL=\"ldap://${instance_hostname}:${server_port}/o=NetscapeRoot\""

    $command = "/usr/sbin/setup-ds-admin.pl $common_args $admin_args"
  } else {
    $command =  "/usr/sbin/setup-ds.pl $common_args"
  }

  exec { "${instance}-ds389-setup":
    # the second version also configures an admin server on 9830.  Could be useful to have available.  
    # command => "/usr/sbin/setup-ds.pl --silent General.FullMachineName=${instance_hostname} General.SuiteSpotGroup=${suite_spot_group} General.SuiteSpotUserID=${suite_spot_user_id} slapd.InstallLdifFile=suggest slapd.RootDN=\"${root_dn}\" slapd.RootDNPwd=\"${root_dn_pass}\" slapd.ServerIdentifier=${instance} slapd.AddOrgEntries=yes slapd.ServerPort=${server_port} slapd.Suffix=${suffix}",    
    command   => "/usr/sbin/setup-ds-admin.pl --silent General.FullMachineName=${instance_hostname} General.SuiteSpotGroup=${suite_spot_group} General.SuiteSpotUserID=${suite_spot_user_id} slapd.InstallLdifFile=suggest slapd.RootDN=\"${root_dn}\" slapd.RootDNPwd=\"${root_dn_pass}\" slapd.SlapdConfigForMC=yes slapd.ServerIdentifier=${instance} slapd.AddOrgEntries=yes slapd.ServerPort=${server_port} slapd.Suffix=${suffix} admin.SysUser=${suite_spot_user_id} General.ConfigDirectoryAdminID=admin General.ConfigDirectoryAdminPwd=\"${root_dn_pass}\" admin.ServerAdminID=admin admin.ServerAdminPwd=\"${root_dn_pass}\" admin.ServerIpAddress=${net::backend::ip} admin.Port=9830 General.ConfigDirectoryLdapURL=\"ldap://${instance_hostname}:${server_port}/o=NetscapeRoot\"",    
    require   => [ Package['389-ds-base'] ],
    creates   => "${database}",
    tag       => "ds389-setup",
    logoutput => false
  } ->
  
  service { "dirsrv@${instance}":
      ensure => $ds389::service_running,
      enable => $ds389::service_enable
  }

  Exec["${instance}-ds389-setup"] ->  Exec <|tag == 'ds389-init' |>  -> File <| tag == 'ds389-ldif' |> 

  $schema_install.each | $schema | {
    ds389::schema { "$schema":  instance => $instance }
  }

  if $enable_ssl {
    # -W is the PKCS12 password, -K is keystore password.    
    # if we don't stop the instance before doing this the import ends up corrupted and doesn't work
    exec { "${instance} import key and certificate":
      command => "${stop} ; /bin/pk12util -i $certfile -d ${database} -W \"$certpass\" -K \"$kspass\" ",
      unless  => [ "/bin/certutil -L -d ${database} | /bin/grep -q \"${certname}\"", "/usr/bin/test ! -f $certfile" ],
      tag => 'ds389-init',
      logoutput => false
    } -> 

    exec { "${instance} import CA chain":
      command => "/bin/certutil -d ${database} -A -n $caname -t CT,, -a -i $cafile; ",
      unless  => [ "/bin/certutil -d ${database} -L | /bin/grep -q \"${caname}\"" , "/usr/bin/test ! -f $cafile" ],
      notify  => Service["dirsrv@${instance}"] 
    } 

    if ($kspass != '') {
      exec { "${instance} setup token":
        command  => "${stop} ;/bin/echo \"Internal (Software) Token:${kspass}\" > ${database}/pin.txt ;chown -R ${suite_spot_user_id}:${suite_spot_group} ${database}*  ;${start}",
        creates  => "${database}/pin.txt",
        tag      => 'ds389-init',
        notify   => Service["dirsrv@${instance}"]  
      }
    }

    ds389::ldif { 'ssl.ldif':
      instance     => $instance,
      root_dn_pass => $root_dn_pass,
      root_dn      => $root_dn,
      template_vars => {       # it seems dumb that I have to do this, but that's scoping for you
        certname => $certname 
      }
    }
  }

  if $enable_replication {
    ds389::ldif { 'replication.ldif':
      instance      => $instance,
      root_dn_pass  => $root_dn_pass,
      root_dn       => $root_dn,
      template_vars => {
        instance       => $instance,
        replica_id     => $replica_id,
        suffix         => $suffix,
        escaped_suffix => $escaped_suffix,
      }
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

      ds389::ldif { 'supplier_bind_dn': 
        instance     => $instance,
        root_dn_pass => $root_dn_pass,
        root_dn      => $root_dn,
        ldif         => $repl_bind_ldif
      }

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

      ds389::ldif { "${replica}-agreement": 
        instance     => $instance,
        root_dn_pass => $root_dn_pass,
        root_dn      => $root_dn,
        ldif         => $repl_ldif
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

