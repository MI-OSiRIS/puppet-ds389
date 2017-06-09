define ds389::schema (
  $instance,
  $file_path = 'ds389/schema',
  $schema_file = "${name}",
  $order       = '65',
) {

$database           = "/etc/dirsrv/slapd-${instance}"
$stop               = "/bin/systemctl stop dirsrv@${instance}"
# $start              = "/bin/systemctl start dirsrv@${instance}"

  exec { "${instance}-stop-install-${schema_file}":
    command => "${stop}", 
    creates => "${database}/schema/${order}${schema_file}",
    tag => 'ds389-init'
  } ->

  file { "${instance}-${schema_file}":
    path => "${database}/schema/${order}${schema_file}",
    content => file("$file_path/$schema_file"),
    notify => Service["dirsrv@${instance}"]
  } 
}

