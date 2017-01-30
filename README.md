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