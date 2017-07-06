# puppet-ds389

A module to configure 389 DS and multimaster replication.  

Works with RHEL7, probably also works with Fedora.  Not tested or targeted at any other distribution.  

Known bugs: 
* Assumes/requires TLS configured if doing replication even if enable_ssl is false.
* Only able to configure multi-master type replication agreements

Sample usage:

<pre>
class { 'ds389': }

$replicas = [ 'repl1.example.com','repl2.example.com', 'repl3.example.com' ]


$root_dn_pass = 'password'
$supplier_dn_pass = 'another_password'

  ds389::site { 'example' :
    root_dn_pass           => 'password',
    supplier_bind_dn_pass  => 'different_password',
    suffix                 => 'dc=example,dc=org',
    cafile                 => '/path/to/ca.pem',
    caname                 => 'Example-CA-Cert',
    certfile               => '/path/to/key_cert.p12',
    enable_ssl             => true,
    enable_replication     => true,
    schema_install         => [ 'eduorg.ldif' ],
    instance_hostname      => "${::hostname}",
    # delete myself from replicas defined on myself
    replicas               => delete($replicas, "${::hostname}"),
    replica_id             => 1,
    replica_init           => false  # only true on 1 of your replicas, run puppet on that one last 
  }
  
  ds389::ldif { 'example.ldif': 
      root_dn_pass  => $root_dn_pass,
      instance      => 'example',
      template_path => 'ldapx'  # lookup templates under ldapx/templates in your module paths 
   }
</pre>

In actual usage you might keep passwords encrypted in hiera eyaml and look them up to pass to the module.  See https://github.com/voxpupuli/hiera-eyaml for information on that.  

The ds389::site resource accepts a list of replicas (not including local machine) and configures appropriate replica agreements. One of the replicas should have the replica_init parameter set to true and this one should have puppet run last after the other replicas are configured and running. So the process to start 3 hosts, with host1 being given the replica_init flag:

1. Generate a key and cert to use for TLS. 
2. The key and cert need to be turned into a pkcs12 keycert whose path will be given as a module param.
3. Configure puppet code to call module appropriately. Ensure 'replica_init' param is not set on host3 and host2, and ensure you specify unique replica_id param for each host. 
4. Stop puppet service on all 3 hosts (so it doesn't surprise you by running on schedule)
5. On host3 run 'puppet agent -t'
6. On host2 run 'puppet agent -t'
7. Verify in /var/log/dirsrv-<instance>/errors and /access that the services on host3 and host2 are running correctly and that SSL/TLS started up. TLS connection is hardcoded into the replication agreements the module creates.
8. On host1 run 'puppet agent -t'
9. Check on replication status with the command noted below.

To check on replication status:
<pre>
ldapsearch -x -b "cn=mapping tree,cn=config" -D "cn=Directory Manager" -W objectClass=nsDS5ReplicationAgreement -LL
</pre>

If something goes wrong, or you choose not to initialize during puppet setup (replica_init false on all 3 hosts) you can initialize manually from any ONE of the replicas. Choose one host and initialize the others from it…do not repeat the initialization on the other hosts. The example below intializes one replica, repeat ldif with other ldap replica(s).

Either run ldapmodify and paste in the block followed by hitting enter twice, pipe it to ldap modify from a file, or specify the file to use with '-f file.ldif':

<pre>
ldapmodify -v -x -D "root_dn" -w root_dn_pass

dn: cn=ExampleAgreementName,cn=replica,cn=dc\=example\,dc\=com,cn=mapping tree,cn=config
changetype: modify
replace: nsds5BeginReplicaRefresh
nsds5BeginReplicaRefresh: start
</pre>

Repeat for each replication agreement on your chosen host (do not re-initialize from other hosts in multi-master config)

More information about setting up and troubleshooting replication from the CLI is available from Redhat.  The instructions below are implemented by this module.  

https://access.redhat.com/documentation/en-US/Red_Hat_Directory_Server/10/html/Administration_Guide/Managing_Replication-Configuring-Replication-cmd.html

Information on monitoring replication status with tools such as Nagios is detailed here:
http://directory.fedoraproject.org/docs/389ds/howto/howto-replicationmonitoring.html

We have a slight revision of the replication check Nagios script available from our Git repository:
https://github.com/MI-OSiRIS/checkmk/blob/master/plugins/check_ds_replication
