Blame Notifier Script for PVS Studio
====================================

This is a simple Perl script which notifies you about new PVS issues.

# Main Features

* Does not require MS .Net, which makes no sense on Linux
* Parses PVS Studio text output (`plog-converter -t errorfile`)
* Stores found issues in database to identify known issues and send email only
  for new issues.
* Extracts commit and author info from Git
* Creates HTML email with annotated source code snippets and PVS issue information
* Sends email to authors (and only to authors of the issues)
* Adding attachments with the full PVS error file.

# Requirements

* The project must be tracked by Git
* A MySql/MariaDB must be set up for tracking issues
* sendmail compatible program must be installed and setup for sending emails
* Perl must be installed, which is normally the case on every Linux machine
* GNU Source Highlighter (optional)

# Installation

The installation require some basic Linux administration skills like setting up
a MySQL DB, so nothing special.

After cloning this repository you need to install the following requirements.

## Install Perl Libraries

This script requires the following Perl modules:

* DBI - Database Calss
* MIME::Lite - Creating Email in MIME format
* YAML - YML parser for loading config files
* List::MoreUtils - Some list utilities like e.g. `uniq`
* Getopt::Std - Command line argument parsing
* FindBin - For finding the installation path of the Perl script
* IPC::Filter (optional, for syntax highlighting)

On Debian based systems you can install them this way:

    $> sudo apt install libdbi-perl libclass-dbi-mysql-perl libmime-lite-perl libyaml-perl liblist-moreutils-perl libgetopt-simple-perl libipc-filter-perl

## Install GNU Source Highlight (optional)

This program is used to create basic syntax highlighting for code fragments.
It's not perfect due the git-blame output-format, but it is better than nothing.

    $> sudo apt install source-highlight

## Install sendmail

On Linux there are different options available like a full MTA (postfix, exim, etc.)
or simple mail senders (ssmtp, msmtp).

On recent Debian systems ssmtp does not exist anymore, so I go for msmtp.

    $> sudo apt install msmtp msmtp-mta

Then create the file /etc/msmtprc:

~~~
# Set default values for all following accounts.
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile /var/log/msmtp.log

# Anderer Account
account        your_account_name
host           smtp.domain.com
port           587
from           pvs-studio@domain.com
user           pvs-studio@domain.com
password       yoursupersecretmailpassword

# Set a default account
account default: your_account_name

# Map local users to mail addresses (for crontab)
aliases /etc/aliases
~~~

Then test if it works:

~~~
$> echo "test message" | mail -s "test" me@domain.com
~~~

See also https://wiki.archlinux.org/index.php/Msmtp for more information.

## Install Database

I go for MariaDB, which is the open source MySQL database. In theory other
databases supported by Perl DBI should work as well, but I have not tested.

~~~
$> sudo apt install mariadb-server
$> sudo mysql_secure_installation
~~~

Then setup the database for blame-notifier.

~~~
$> sudo mysql
mysql> CREATE DATABASE blame;
mysql> GRANT ALL on blame.* TO 'blame'@'localhost' IDENTIFIED BY 'secret_mysql_password';
mysql> quit
~~~

These SQL commands setup a new database called 'blame' and a new user 'blame',
that is only allowed to connect from localhost and only has access to the 'blame' db.

## Configuration

The blame-notifier tool reads a configuration file. It will search in two locations
for this file:

 * `/etc/blame.cfg`
 * `$HOME/.blame.cfg`

If both are available both will be loaded, so that the later can override options
from the global config file. The file contents is in YAML format.

```yml
---
# database connection string
dsn: DBI:mysql:blame
# database username
username: blame
# database password
password: secret_mysql_password
# smtp sender address
smtp_from: pvs-studio@domain.com
# smtp subject
smtp_subject: New PVS Issues
# path substitution
path_search: '/root/src/src/'
path_replace: ''
```

You can create the file by copying the sample config and setting correct file permissions.
Because this file contains credentials it should not be world readable.

```sh
$> sudo cp blame.cfg.sample /etc/blame.cfg
$> sudo chmod 600 /etc/blame.cfg
$> sudoedit /etc/blame.cfg
````

# Usage

The basic usage is like this:

```
$> ./blame-notifier.pl < pvs-report/errors.txt
```

Use the option `-h` to get a list of all available options.

## Testing

Instead of sending email to all your developers you should use a test email address first,
which overrides the recipient mail addresses extracted from Git.

```
$> ./blame-notifier.pl -r me@domain.com < pvs-report/errors.txt
```

The emails will be sent only once for each found issue. If you want to forget
all stored issues in the DB add the option `-d`, which will create SQL DROP
TABLE statement and recreates the database table.

```
$> ./blame-notifier.pl -d -r me@domain.com < pvs-report/errors.txt
```

Another option is `-v`, which adds some verbose output to see what is going on.

## Advanced options

### Adding Attachments

You can add attachments to the mail like the PVS report itself or the html variant of it.
Therefor use the `-a` options which takes a comma separated list of filenames.

```
$> ./blame-notifier.pl -a 'pvs-report/errors.txt,pvs-report/errors.html' < pvs-report/errors.txt
```

### Path substitution

When running the PVS build in Docker, but blame-notifier on the host system, the paths of the PVS error report might not match.
In this case you can configure path substitution in the `blame.cfg` configuration file.

```
# path substitution
path_search: '/guest/path/to/project/'
path_replace: '/host/path/to/project'
```

This will substitute the paths of errors.txt before calling _git_ to extract information.

## Debugging

For Debugging, or better say tracing, you can enable the Smart::Comments in the Perl code.
Or use the Perl debugger `perl -d:ptkdb <file>`.

# Final Notes

You should not run this as root normally, because this never is a good idea. Msmtp may require
to use a config file in the users home directory.

In our case we run the whole CI and the PVS analyze script in a Docker container.
This means you need to setup the 'sendmail' tool in Docker. The database should be installed
on the host system. You can bind the mysql unix domain socket to the container using Docker's
`-v` option.

An alternative solution is mounting a shared folder into the Docker guest, where the PVS results
are saved and then run the blame-notifier on the host system. The advantage of this concept is,
that you don't need to setup blame-notifier in every docker container.

# Future Improvements

We could add the option to send plaintext mails instead of HTML mails, which are preferred by many developers.
Or just use multipart mails correctly and offer HTML as well as a plaintext part.

# Tip for Vim Users

As a Vim user you can easily jump to error locations using the normal Vim Quickfix cycle.
All you need to do is opening the attached `errors.txt` file, substitute the file paths to match your local checkout
and use `:cbuffer` to convert the buffer into an error list.

Lets assume the build server has checked out the project 'demo' in `/home/buildbot/work/src`
und you have it in `/home/myname/work/demo`. Then you would do the following:

```
$> vim errors.txt
:%s|^/home/buildbot/work/src|/home/myname/work/demo|
:cbuffer
```

Enjoy the power of Vim!

