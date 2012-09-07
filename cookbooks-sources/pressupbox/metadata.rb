maintainer       "PressUpBox"
maintainer_email "david@davidlaing.com"
license          "Apache v2"
description      "Combines a set of cookbooks to create a working PressUpBox"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.5.1"

recipe            "pressupbox", "Combines a set of cookbooks to create a working PressUpBox"
recipe            "pressupbox::mirror", "Mirror all or part of this PressUpBox to another"
recipe            "pressupbox::move_mysql_data_dir", "Installs mysql_server with custom data_dir in Ubuntu"

depends			 "apache2"
depends			 "apache2-mpm-itk"
depends			 "apparmor"
depends			 "build-essential"
depends			 "apt"
depends			 "hostname"
depends			 "htop"
depends			 "multitail"
depends			 "mysql"
depends			 "nginx"
depends			 "ossec"
depends			 "php"
depends			 "postfix"
depends			 "rsync"
depends			 "runit"
depends			 "timezone"
depends			 "unarchivers"
depends			 "xml"
depends			 "app_containers"
depends			 "wp-cli"
