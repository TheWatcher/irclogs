package Irssi::Logbot;

use strict;
use Irssi;
use DBI;
use Time::HiRes qw(gettimeofday);

# ============================================================================
#  Constructor

## @cmethod LogbotDB new(%args)
# Create a new LogbotDB object. This will create an LogbotDB object that may be
# used to log IRC messages. If the arguments hash contains the settings needed
# to open the database connection, and autoconnect is set to true, this will
# attempt to connect to the database, otherwise you will need to call
# connection_settings() or connect() to set up the connection. The following
# arguments may be povided in the argument hash:
#
# - `database`: the name of the MySQL database to connect to (note that this may
#               contain a host and port if desired: `foo@bar.com:1234` will connect
#               to the database `foo` on the server on `bar.com` port 1234.
# - `username`: the name of the user to connect with.
# - `password`: the password to provide with the username.
#
# @param args A hash of arguments to initialise the settings with.
# @return A reference to a new LogbotDB object.
sub new {
    my $invocant = shift;
    my $class    = ref($invocant) || $invocant;

    my $self = {
        "settings" => {
            "autoconnect" => 0,
            "database"    => undef,
            "username"    => undef,
            "password"    => undef,
            @_,
        },
        "tables" => {
            "messages"  => "messages",
            "servers"   => "servers",
            "channels"  => "channels",
            "nicks"     => "nicks",
            "logtypes"  => "types",
            "usermodes" => "usermodes",
        },
    };

    return bless $self, $class;
}


sub get_logger {


}


## @method $ connection_settings($database, $username, $password, $table, $set_only)
# Update the database connection settings. This changes the settings used to
# connect to the database, and reconnects to the database using the new settings
# (unless set_only is true, in which case no disconnect/connect is done).
#
# @param database The name of the MySQL database to connect to.
# @param username The username to use during connection.
# @param password The password to authenticate with.
# @param table    The name of the table in the database to log messages in.
# @param set_only If true, this function will set the database connection settings,
#                 but it will not disconnect any existing database connection, or
#                 open a new connection. If false (or omitted), this function will
#                 disconnect from any existing database and connect with the new settings.
# @return true if successful, false otherwise.
sub connection_settings {
    my $self = shift;

    # Pull the rest of the settings out of the argument list...
    $self -> {"settings"} -> {"database"} = shift;
    $self -> {"settings"} -> {"username"} = shift;
    $self -> {"settings"} -> {"password"} = shift;
    $self -> {"settings"} -> {"table"}    = shift;

    # If set_only is set, we're done here.
    my $set_only = shift;
    return 1 if($set_only);

    # Otherwise, reconnect. connect() will disconnect any existing connection.
    return $self -> connect();
}


## @method $ connect()
# Attempt to connect to the database specified by the user. This will try to
# establish a database connection through which messages may be logged. Any
# errors encountered will be printed to the user. If a database connection is
# already active, this will close the connection before attempting to open a
# new one.
#
# @return true if the database connection was successful, false otherwise.
sub connect {
    my $self = shift;

    # Disconnect any existing database if needed
    $self -> database_disconnect();

    # Only attempt to open the database connection if the settings are present.
    if($self -> {"settings"} -> {"database"} && $self -> {"settings"} -> {"username"} && $self -> {"settings"} -> {"password"} && $self -> {"settings"} -> {"table"}) {
        $self -> {"dbh"} = $DBI -> connect_cached("DBI:mysql:".$self -> {"settings"} -> {"database"},
                                                  $self -> {"settings"} -> {"username"},
                                                  $self -> {"settings"} -> {"password"},
                                                  # RaiseError could be 1 here, but risks killing irssi unless everything is eval wrapped.
                                                  { RaiseError => 0, AutoCommit => 1, mysql_enable_utf8 => 1 });

        # Did the database connection work? If so, prepare the insert statement for later.
        if($self -> {"dbh"}) {
            return 1;

        # Keep the user informed of errors during connection.
        } else {
            Irssi::print("logbot[ERROR]: database connection failed: ".$DBI::errstr, CLIENTERROR);
        }
    } else {
        Irssi::print("logbot[ERROR]: unable to open database connection due to missing settings.", CLIENTERROR);
    }

    # Failed, go away.
    return 0;
}


## @method void disconnect()
# Close the connection to the database, if it is open. This will check whether
# the database is open, and if it is it will close it cleanly. Note that this will
# always succeed - even if it fails: DBD::mysql will always assume that its
# disconnect worked, and always returns true, so this has to assume it worked too!
sub disconnect {
    my $self = shift;

    # Do nothing if the database connection is not open
    return unless($self -> {"dbh"});

    # The docs suggest this can return false. At least in the case of DBD::mysql
    # they lie like a lying thing, so this assumes disconnect always works (as
    # DBD::mysql does!)
    $self -> {"dbh"} -> disconnect();

    # Ensure that inserts can't be attempted without a database.
    $self -> {"dbh"}          = undef;
}


## @method $ log($type, $nick, $usermode, $useraddr, $channel, $serveraddr, $message)
# Log an IRC message in the log table. If the database connection is open, and the
# database is still working, this will attempt to store the specified message data
# in the log table. If this is called before the connection is opened, or the
# database can not be ping()ed, it is effectively a noop.
#
#
sub log {
    my $self = shift;
    my ($type, $nick, $usermode, $useraddr, $channel, $serveraddr, $message) = @_;

    # Would be nice to get this simply as fractional seconds, but MySQL has no time
    # fields that support that. And multiplying the fractional version hits possible
    # byte size issues if longsize < 8. Needs must when the devil vomits into your kettle.
    my ($timestamp, $millis) = gettimeofday();

}


sub lookup_nick {
    my $self = shift;
    my $nick = shift;

    # Is the nick cached?
    return $self -> {"cache"} -> {"nicks"} -> {$nick} if($self -> {"cache"} -> {"nicks"} -> {$nick});

    # No cache, does the nick exist in the database?
    my $nickh = $self -> {"dbh"} -> prepare("SELECT id FROM ".$self -> {"tables"} -> {"nicks"}."
                                             WHERE nick LIKE ?");
    $nickh -> execute($nick)
