define ds389::schema (
  $instance,
  $file_path   = 'ds389/schema',
  $schema_file = "${name}",
  $order       = '65',
) {

  $database = "/etc/dirsrv/slapd-${instance}"

  file { "${instance}-${schema_file}":
    path => "${database}/schema/${order}${schema_file}",
    content => file("$file_path/$schema_file"),
    notify => Service["dirsrv@${instance}"]
  }

}

