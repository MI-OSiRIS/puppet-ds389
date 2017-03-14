# puppet-ds389

A module to configure 389 DS and multimaster replication

Works with RHEL7, probably also works with Fedora.  Not tested or targeted at any other distribution.  

Sample usage:

<pre>
class { 'ds389': }

$replicas = [ 'repl1.example.com','repl2.example.com', 'repl3.example.com' ]

ds389::site { 'example' :
	require			           	=> Exec['ds389 osiris generate keycert'],
	root_dn_pass           		=> 'password',
	supplier_bind_dn_pass  		=> 'password,
	suffix                 		=> 'dc=example,dc=com',
	cafile 			           	=> '/path/to/ca.pem',
	caname			           	=> 'CA-Cert',
	certfile 		           	=> '/path/to/keycert.p12',
	ldif_install           		=> [ 'ssl.ldif', 'replication.ldif' ],
	instance_hostname      		=> "$::fqdn", 
	# delete myself from replicas defined on myself
	replicas               		=> delete($replicas, "${::fqdn}"),
	replica_id             		=>  1  # unique id from 1 to 65536 for each replica
	replica_init           		=> false  # should only be true on one replica, and this should be the last one you setup.  
}
</pre>

If setting up with replication, only one replica host should have replica_init set to true.  This host should be the last host to have this module applied after the other ones are up and running.  It will then initialize the replica agreements with the other 2 hosts.  

You can also leave the setting false, set up all the hosts, and initialize the agreements with ldapmodify input similar to the following.  Either run ldapmodify and paste in the block followed by hitting enter twice, pipe it to ldap modify from a file, or specify the file to use with '-f file.ldif'.

<pre>
ldapmodify -v -x -D "root_dn" -w root_dn_pass

dn: cn=ExampleAgreementName,cn=replica,cn=dc\=example\,dc\=com,cn=mapping tree,cn=config
changetype: modify
replace: nsds5BeginReplicaRefresh
nsds5BeginReplicaRefresh: start
</pre>

Repeat for each replication agreement.

More information about setting up and troubleshooting replication from the CLI is available from Redhat.  The instructions below are implemented by this module.  

https://access.redhat.com/documentation/en-US/Red_Hat_Directory_Server/9.0/html/Administration_Guide/Managing_Replication-Configuring-Replication-cmd.html
