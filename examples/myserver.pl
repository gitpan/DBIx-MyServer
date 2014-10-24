#!/usr/bin/perl

=pod

=head1 SYNOPSIS

	perl examples/myserver.pl --config=examples/myserver.conf --port=1234 --dsn="dbi:mysql:"

	mysql -h127.0.0.1 -P1234 -umyuser -e 'info'

=head1 DESCRIPTION

This is a simple server that listens for incoming connections from MySQL clients or connectors.

Each query received is processed according to a set of configuration files, which can rewrite the query,
forward it to a DBI handle or construct a response or a result set on the fly from any data.

=head1 COMMAND LINE OPTIONS

C<--port=XXXX> - port to listen on. Default is C<23306>, which is the default MySQL port with a 2 in front.

C<--interface=AAA.BBB.CCC.DDD> - interface to listen to. Default is C<127.0.0.1> which means that only connections from the localhost
will be accepted. To enable connections from the outside use C<--interface=0.0.0.0>. In this case, please make sure
you have some other form of access protection, e.g. like the first rule in the C<myserver.conf> example configuration file.

C<--config=config.file> - a configuration file containing rules to be executed. The option can be specified multiple times
and the rules will be checked in the order specified.

C<--dsn> - specifies a L<DBI> DSN. All queries that did not match a rule or where the rule rewrote the query or did not
return any response or a result set on its own will be forwarded to that database. Individual rules can forward specific
queries to specific DSNs. If you do not want non-matching queries to be forwarded, either create a match-all rule at
the bottom of your last configuration file or omit the C<--dsn> option. If you omit the option, an error message will be
sent to the client.

C<--dsn_user> and C<--dsn_password> can be used to specify username and password for DBI drivers where those can not be
specified in the DSN string.

=head1 RULES

Rules to be executed are contained in configuration files. The configuration files are actually standard perl scripts and
are executed as perl subroutines. Therefore, they can contain any perl code -- the only requirement is that the last
statement in the file (that is, the return value of the file) is an array containing the rules to be executed.

The actions from a rule will be executed for all queries that match a specific pattern. Rules are processed in order
and processing is terminated at the first rule that returns some data to the client. This allows you to rewrite a query
numerous times and have a final default rule that forwards the query to another server. If C<forward> is defined, further
rules are not processed.

Each rule can have the following attributes:

C<command> The rule will match if the MySQL command issued by the client matches C<command>. C<command> can either be
an integer from the list found at C<DBIx::MyServer.pm> or a reference to a C<SUB> that returns such an integer. This is
mainly useful for processing incoming C<COM_PING>, C<COM_INIT_DB> and C<COM_FIELD_LIST>.

C<match> The rule will match if the test of the query matches a regular expression or is identical to a string. C<match>
can also be a reference to a C<SUB> in which case the sub is executed and can either return a string or a regular expression.

If both C<command> and C<match> are specified, both must match for the rule to be executed.

C<dbh> if specified, any matching query will be forwarded to this database handle (possibly after a C<rewrite>), rather
than the default handle specifeid on the command line.

C<dsn> behaves identically, however a database handle is contructed from the C<dsn> provided and an attempt is made to
connect to the database. If C<dsn> is a reference to an array, the first item from the array is used as a DSN, the second
one is used as username and the third one is used as password.

C<before> this can be a reference to a subroutine that will be called after a matching query has been encountered but before
any further processing has taken place. The subroutine will be called with the text of the query as the first argument,
followed by extra arguments containing the strings matched from any parenthesis found in the C<match> regular expression.
You can use C<before> to execute any extra queries before the main query, such as C<EXPLAIN>. The return value from the
C<before> subroutine is discarded and is not used.

C<rewrite> is a string that will replace the original query that matches the rule, or a reference to a subroutine that
will produce such a string. If C<rewrite> is not defined, and C<match> was a string, the query is passed along unchanged.
If C<match> was a regular expression, the string matched by the first set of parenthesis is used. This way, if the rule
does not specify any C<data>, C<columns>, C<error> or C<ok> clauses, but a valid DBI handle is defined, the query
will be forwarded to that handle automatically.

C<error> can be either an array reference containing three arguments for C<DBIx::MyServer::sendError()> or a reference to
a subroutine returning such an array (or array reference). If this is the case, the error message will be sent to the client.
If C<error> is not defined or the subroutine returns C<undef>, no error message will be sent. In this case, you need to
send at some point either an C<ok> or a result set, otherwise the client will hang forever waiting for a response.

C<ok> behaves identically to C<error> -- if it is defined or points to a subroutine which, when called, returns a true value,
an OK response will be sent to the client. C<ok> can also be a reference to an array, or the subroutine can return such an
array -- in this case the first item is the message to be sent to the client, the second one is the number of affected rows,
the third is the insert_id and the last one is the warning count.

C<columns> must contain either an array reference or a reference to a subroutine which returns and array or array reference.
The column names from the array will be sent to the client. By default, all columns are defined as C<MYSQL_TYPE_STRING>.

C<data> must contain either a reference to the data to be returned to the client or a reference to subroutine that will
produce the data. "Data" can be a reference to a C<HASH>, in which case the hash will be sent with the key names in the
first column and the key values in the second. It can be a flat array, in which case the array items will be sent as 
a single column, or it can be a reference to a nested array, with each sub-array being a single row from the response.

C<after> is called after all other parts of the rule have been processed.

C<forward> if defined, the query will be immediately forwarded to the server and no further rules will be processed.

All subroutine references that are called will have the text of the query passed as the first argument and the subsequent
arguments will be any strings matched by parenthesis in the C<match> regular expression.

=head1 VARIABLES

Your code in the configuration file can save and retrieve state by using C<get($variable)> and C<set($variable, $value)>.
State is retained as long as the connection is open. Each new connection starts with a clean state. The following
variables are maintained by the system:

C<myserver> contains a reference to the L<DBIx::MyServer> object being used to service the connection. You can use this to
inject data and packets directly into the network stream.

C<username> contains the username provided by the client at connection establishment.

C<database> contains the database requested by the client at connection establishment. By default, C<myserver.pl> will
not automatically handle any database changes requested by the client. You are responsible for handling those either by
responding with a simple OK or by updating the variables.

C<remote_host> contains the IP of the client.

C<dbh> and C<dsn> will contain a reference to the default DBI handle and the DSN string it was produced from, as taken
from the command line. Even if a specific rule has its own C<dsn>, the value of those variables will always refer to
the default C<dbh> and C<dsn>. If you change the <dsn> variable, the system will attempt to connect to the new dsn string
and will produce a new C<dbh> handle from it. If you set C<dsn> to an array reference, the first item will be used as
a DSN, the second one as a username and the third one as a password. C<dsn_user> and C<dsn_password> can be used for the
same purpose.

C<args> contains a reference to the C<@ARGV> array, that is, the command line options that evoked myserver.pl

C<remote_dsn>, C<remote_dsn_user> and C<remote_dsn_password> are convenience variables that can also be specified on the
command line. It is not used by C<myserver.pl> however you can use it in your rules, the way C<remotequery.conf> does.

=head1 SECURITY

IMPORTANT NOTICE: THIS SCRIPT IS MEANT FOR DEMONSTRATION PURPOSES ONLY AND SHOULD NOT BE ASSUMED TO BE SECURE BY ANY MEANS!

By default the script will only accept incoming connections from the local host. If you relax that via the C<--interface>
command-line option, all connections will be accepted. However, once the connection has been established, you can implement
access control as demonstrated in the first rule of the C<myserver.conf> file -- it returns "Access denied" for every query
unless the username is "myuser". Future versions of the script will allow connections to be rejected during handshake.

The script expects that the password is equal to the username. This is currently hard-coded.

=head1 SAMPLE RULES

The following rule sets are provided in the C<examples/> directory.

=head2 Simple examples - myserver.conf

This configuration provides some simple query rewriting examples as suggested by Giuseppe Maxia and Jan Kneschke, e.g.
commands like C<ls>, C<cd> as well as fixing spelling mistakes. In addition, some very simple access control is demonstrated
at the top of the file.

=head2 Remote queries - remotequery.conf

This rule set implements a C<SELECT REMOTE select_query ON 'dsn'> operator which will execute the query on <dsn> specified,
bring the results back into a temporary table on the default server and substitute the C<REMOTE_SELECT> part in the orignal
query with a reference to the temoporary table. The following scenarios are possible:

	# Standalone usage
	mysql> SELECT REMOTE * FROM mysql.user ON 'dbi:mysql:host=remote:user=foo:password=bar'

	# CREATE ... SELECT usage
	mysql> CREATE TABLE local_table SELECT REMOTE * FROM remote_table ON 'dbi:mysql:host=remote'

	# Non-correlated subquery
	mysql> SELECT *
	mysql> FROM (SELECT REMOTE * FROM mysql_user ON 'dbi:mysql:host=remote:user=foo:password=bar')
	mysql> WHERE user = 'mojo'

	# Specify remote dsn on the command line
	shell> ./myserver.pl --config=remotequery.conf --dsn=dbi:mysql: --remote_dsn=dbi:mysql:host=host2
	mysql> select remote 1;

	# Specify remote dsn as variable

	mysql> set @@@remote_dsn=dbi:mysql:host=host2
	mysql> select remote NOW();

	mysql> set @@@devel_dsn=dbi:mysql:host=dev3
	mysql> select remote NOW() ON @@@devel_dsn; 

This is different from using the Federated storage handler because the entire C<REMOTE_SELECT> query is executed on the
remote server and only the result is sent back to the default server for further processing. This is useful if a lot of 
processing is to be done on the remote server -- the Federated engine will bring most of the data to the connecting server
and will process it there, which can potentially be very time consuming.

Please note that since a temporary table is created and it must reside somewhere, you need to be in a working database
on the default server. Updateable C<VIEW>a are not supported.

=head2 Development support - devel.conf

This configuration provides the following operators:

C<shell> - can be used to execute shell commands, e.g. C<shell ls -la>.
C<env> - returns the operating environment of C<myserver.pl>.
C<stats> - executes C<SHOW STATUS> before and after each query and returns the difference. First you execute
C<stats select a from b> and then C<show stats>.
C<devel> - can be used to send specfic queries to a different server. You can execute a single query as
C<devel select a from b> or use a standalone C<devel> to redirect all future queries until you issue C<restore>.

You specify the server to send "development" queries to via C<set('devel_dsn')> at the top of C<devel.conf>

=head2 ODBC compatibility - odbc.conf

The C<odbc.conf> contains an example on how to unintelligently answer generic queries sent by the MySQL ODBC driver and
the applications that use it, up to the point where real data can be sent over the connection and imported into the client
application.

=cut

use strict;
use Socket;
use DBI;
use DBIx::MyServer;
use DBIx::MyServer::DBI;
use Getopt::Long qw(:config pass_through);


$SIG{CHLD} = 'IGNORE';

my $start_dsn;
my $start_dsn_user;
my $start_dsn_password;

my $remote_dsn;
my $remote_dsn_user;
my $remote_dsn_password;

my $port = '23306';
my $interface = '127.0.0.1';
my $debug;
my @config_names;
my @rules;
my %storage;

my @args = @ARGV;

my $result = GetOptions(
	"dsn=s"			=> \$start_dsn,
	"dsn_user=s"		=> \$start_dsn_user,
	"dsn_password=s"	=> \$start_dsn_password,
	"remote_dsn=s"		=> \$remote_dsn,
	"remote_dsn_user=s"	=> \$remote_dsn_user,
	"remote_dsn_password=s"	=> \$remote_dsn_password,
	"port=i"		=> \$port,
	"config=s"		=> \@config_names,
	"if|interface|ip=s"	=> \$interface,
	"debug"			=> \$debug
) or die;

@ARGV = @args;

my $start_dbh;
if (defined $start_dsn) {
	print localtime()." [$$] Connecting to DSN $start_dsn.\n" if $debug;
	$start_dbh = DBI->connect($start_dsn, $start_dsn_user, $start_dsn_password);
}

$storage{dbh} = $start_dbh;
$storage{dsn} = $start_dsn;
$storage{dsn_user} = $start_dsn_user;
$storage{dsn_password} = $start_dsn_password;

$storage{remote_dsn} = $remote_dsn;
$storage{remote_dsn_user} = $remote_dsn_user;
$storage{remote_dsn_password} = $remote_dsn_password;

foreach my $config_name (@config_names) {
	my $config_sub;
	open (CONFIG_FILE, $config_name) or die "unable to open $config_name: $!";
	read (CONFIG_FILE, my $config_text, -s $config_name);
	close (CONFIG_FILE);
	eval ('$config_sub = sub { '.$config_text.'}') or die $@;
	my @config_rules = &$config_sub();
	push @rules, @config_rules;
	print localtime()." [$$] Loaded ".($#config_rules + 1)." rules from $config_name.\n" if $debug;
}

socket(SERVER_SOCK, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
setsockopt(SERVER_SOCK, SOL_SOCKET, SO_REUSEADDR, pack("l", 1));
bind(SERVER_SOCK, sockaddr_in($port, inet_aton($interface))) || die "bind: $!";
listen(SERVER_SOCK,1);

print localtime()." [$$] Note: port $port is now open on interface $interface.\n";
while (1) {
	my $remote_paddr = accept(my $remote_socket, SERVER_SOCK);

	if (!defined(my $pid = fork)) {
		die "cannot fork: $!";
	} elsif ($pid) {
		next;
	}

	$storage{dbh} = $start_dbh->clone() if defined $start_dbh;
	$storage{dsn} = $start_dsn;
	$storage{args}= \@ARGV;
	
	my $dbh = get('dbh');
	my $myserver = DBIx::MyServer::DBI->new(
		socket => $remote_socket,
		dbh => $dbh,
		banner => $0.' '.join(' ', @ARGV)
	);
	set('myserver', $myserver);

	$myserver->sendServerHello();
	my ($username, $database) = $myserver->readClientHello();
	set('username', $username); set('database', $database);

	if (!$myserver->passwordMatches($username)) {
		$myserver->sendError("Authorization failed. Password must equal username '$username'.",1044, 28000);
		exit();
	}

        eval {
		my $hersockaddr = getpeername($myserver->getSocket());
		my ($port, $iaddr) = sockaddr_in($hersockaddr);
		my $remote_host = inet_ntoa($iaddr);
		set('remote_host', $remote_host);
        };
	
	$myserver->sendOK();

	while (1) {
		my ($command, $query) = $myserver->readCommand();
		print localtime()." [$$] command: $command; data = $query\n" if $debug;
		last if (not defined $command) || ($command == DBIx::MyServer::COM_QUIT);

		my $outgoing_query = $query;

		foreach my $i (0..$#rules) {

			my $rule = $rules[$i];
			my $rule_matches = 0;

			my @placeholders;

			if (defined $rule->{command}) {
				if ($command == $rule->{command}) {
					$rule_matches = 1;
				} else {
					next;
				}
			} 

			my $match_type = ref($rule->{match});
			if (defined $rule->{match}) {
				$rule->{match_string} = $match_type eq 'CODE' ? $rule->{match}($query) : $rule->{match};
				if (ref($rule->{match_string}) eq 'Regexp') {
					$rule_matches = 1 if @placeholders = $query =~ $rule->{match};
				} else {
					$rule_matches = 1 if $query eq $rule->{match_string};
				}
				print localtime()." [$$] Executing 'match' from rule $i: $rule->{match_string}, result is $rule_matches.\n" if $debug;
			} else {
				$rule_matches = 1;
			}
			$rule->{placeholders} = \@placeholders;

			next if $rule_matches == 0;

			my ($definitions, $data);

			undef $storage{data_sent};

			if (defined $rule->{before}) {
				print localtime()." [$$] Executing 'before' from rule $i\n" if $debug;
				eval{
					$rule->{before}($query, @{$rule->{placeholders}});
				};
				error($@) if defined $@ && $@ ne '';
			}

			if (defined $rule->{rewrite}) {
				if (ref($rule->{rewrite}) eq 'CODE') {
					$outgoing_query = $rule->{rewrite}($query, @{$rule->{placeholders}});
				} else {
					$outgoing_query = $rule->{rewrite};
				}
				print localtime()." [$$] Executing 'rewrite' from rule $i, result is '$outgoing_query'\n" if $debug;
			} elsif (defined $rule->{match}) {
				$outgoing_query = $rule->{match_string} eq 'Regexp' ? $rule->{placeholders}->[0] : $outgoing_query;
			}

			if (defined $rule->{error}) {
				my @error = ref ($rule->{error}) eq 'CODE' ? $rule->{error}($query, @{$rule->{placeholders}}) : $rule->{error};
				my @mid_error = ref($error[0]) eq 'ARRAY' ? @{$error[0]} : @error;
				if (defined $mid_error[0]) {
					print localtime()." [$$] Sending error: ".join(', ', @mid_error).".\n" if $debug;
					error(@mid_error);
				}
			}

			if (defined $rule->{ok}) {
				my @ok = ref ($rule->{ok}) eq 'CODE' ? $rule->{ok}($query, @{$rule->{placeholders}}) : $rule->{ok};
				my @mid_ok = ref($ok[0]) eq 'ARRAY' ? @{$ok[0]} : @ok;
				if (defined $mid_ok[0]) {
					print localtime()." [$$] Sending OK: ".join(', ', @mid_ok).").\n" if $debug;
					ok(@mid_ok);
				}
			}

			if (defined $rule->{columns}) {
				my @column_names = ref($rule->{columns}) eq 'CODE' ? $rule->{columns}($query, @{$rule->{placeholders}}) : $rule->{columns};
				my $column_names;
				if (defined $column_names[1]) {
					$column_names = \@column_names;
				} elsif (ref($column_names[0]) eq 'ARRAY') {
					$column_names = $column_names[0];
				} elsif (defined $column_names[0]) {
					$column_names = [ $column_names[0] ];
				}
				print localtime()." [$$] Converting column_names into definitions.\n" if $debug;
				$definitions = [ map { $myserver->newDefinition( name => $_ ) } @$column_names ];
			}

			if (defined $rule->{data}) {
				my @start_data = ref($rule->{data}) eq 'CODE' ? $rule->{data}($query, @{$rule->{placeholders}}) : $rule->{data};
				my $mid_data = defined $start_data[1] ? \@start_data : $start_data[0];

				if (ref($mid_data) eq 'HASH') {
					print localtime()." [$$] Converting data from hash.\n" if $debug;
					$data = [ map { [ $_, $mid_data->{$_} ] } sort keys %$mid_data ];
				} elsif ((ref($mid_data) eq 'ARRAY') && (ref($mid_data->[0]) ne 'ARRAY')) {
					print localtime()." [$$] Converting data from a flat array.\n" if $debug;
					$data = [ map { [ $_ ] } @$mid_data ];
				} elsif (ref($mid_data) eq '') {
					$data = [ [ $mid_data ] ];
				} else {
					$data = $mid_data;
				}
			}

			if (
				(not defined $storage{data_sent}) && (not defined $definitions) && (not defined $data) &&
				( ($i == $#rules) || (defined $rule->{dbh}) || (defined $rule->{forward}) )
			) {
				if (defined $rule->{dbh}) {
					$myserver->setDbh($rule->{dbh});
				} elsif (defined $rule->{dsn}) {
					if (ref($rule->{dsn}) eq 'ARRAY') {
						print localtime()." [$$] Connecting to DSN $rule->{dsn}->[0].\n" if $debug;
						$myserver->setDbh(DBI->connect(@{$rule->{dsn}}));
					} else {
						print localtime()." [$$] Connecting to DSN $rule->{dsn}.\n" if $debug;
						$myserver->setDbh(DBI->connect($rule->{dsn}, get('dsn_user'), get('dsn_password')));
					}
				}
				if (not defined get('dbh')) {
					error("No --dbh specified. Can not forward query.",1235, 42000);
				} elsif ($command == DBIx::MyServer::COM_QUERY) {
					(my $foo, $definitions, $data) = $myserver->comQuery($outgoing_query);
				} elsif ($command == DBIx::MyServer::COM_INIT_DB) {
					(my $foo, $definitions, $data) = $myserver->comInitDb($outgoing_query);
				} else {
					error("Don't know how to handle command $command.",1235, 42000);
				}
				$storage{data_sent} = 1;
			}

			if (defined $definitions) {
				print localtime()." [$$] Sending definitions.\n" if $debug;
				$myserver->sendDefinitions($definitions);
				$storage{data_sent} = 1;
			}
			
			if (defined $data) {
				print localtime()." [$$] Sending data.\n" if $debug;
				$myserver->sendRows($data);
				$storage{data_sent} = 1;
			}
		
			if (defined $rule->{after}) {
				print localtime()." [$$] Executing 'after' for rule $i\n";
				$rule->{after}($query, @{$rule->{placeholders}})
			}

			last if defined $storage{data_sent};
		}

	}

	print localtime()." [$$] Exit.\n";
	exit;
}

sub set {
	my ($name, $value) = @_;
	$storage{$name} = $value;
	if ($name eq 'dsn') {
		if (defined $value) {
			my $dbh;
			if (ref($value) eq 'ARRAY') {
				print localtime()." [$$] Connecting to DSN $value->[0].\n" if $debug;
				$dbh = DBI->connect(@{$value});
			} else {
				print localtime()." [$$] Connecting to DSN $value.\n" if $debug;
				$dbh = DBI->connect($value, get('dsn_user'), get('dsn_password'));
			}
			$storage{myserver}->setDbh($dbh);
			$storage{dbh} = $dbh;
		} else {
			$storage{myserver}->setDbh(undef);
			$storage{dbh} = undef;
		}
	}
	return 1;
}

sub error {
	my $myserver = get('myserver');
	$myserver->sendError(@_);
	$storage{data_sent} = 1;
}

sub error_dbi {
	my $myserver = get ('myserver');
	my $dbh = $_[0] || get ('dbh');
	$myserver->sendErrorFromDBI($dbh);
	$storage{data_sent} = 1;
}

sub ok {
	my $myserver = get('myserver');
	if ($_[0] == 1) {
		$myserver->sendOK();
	} else {
		$myserver->sendOK(@_);
	}
	$storage{data_sent} = 1;
}

sub disconnect { exit; }

sub get {
	return $storage{$_[0]};
}

