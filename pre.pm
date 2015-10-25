##
# PreBot module for ZNC IRC Bouncer
# Author: m4luc0
# Version: 1.0
## #

package pre;
use base 'ZNC::Module';

use POE::Component::IRC::Common; # Needed for stripping message colors and formatting
use DBI;                         # Needed for DB connection
use experimental 'smartmatch';   # Smartmatch (Regex) support for newer perl versions

# (My)SQL settings
my $DB_NAME     = 'db';      # DB name
my $DB_TABLE    = 'table';   # TABLE name
my $DB_HOST     = 'host';   # DB host
my $DB_USER     = 'dbuser';      # DB user
my $DB_PASSWD   = 'dbpassword';      # DB user passwd

# DB Columns
my $COL_PRETIME = 'ctime';     # pre timestamp
my $COL_RELEASE = 'rlsname';     # release name
my $COL_SECTION = 'section';     # section name
my $COL_FILES   = 'files';       # number of files
my $COL_SIZE    = 'size';        # release size
my $COL_STATUS  = 'status';      # 0:pre; 1:nuked; 2:unnuked; 3:delpred; 4:undelpred;
my $COL_REASON  = 'nukereason';      # reason for nuke/unnuke/delpre/undelpre
my $COL_GROUP   = 'grp';       # groupname

my $ANNOUNCE_NETWORK = 'ime';

# Module only accessible for users.
# Comment the next line if you want to make it global accessible
#sub module_types { $ZNC::CModInfo::UserModule }

# Module description
sub description {
    "PreBot Perl module for ZNC"
}

# On channel message
sub OnChanMsg {
    # get message informations
    my $self = shift;
    my ($nick, $chan, $message) = @_;

    # Strip colors and formatting
    if (POE::Component::IRC::Common::has_color($message)) {
        $message = POE::Component::IRC::Common::strip_color($message);
    }
    if (POE::Component::IRC::Common::has_formatting($message)) {
        $message = POE::Component::IRC::Common::strip_formatting($message);
    }
    # DEBUG -> everything is working till here so go on and send me the message
    # $self->PutModule("[".$chan->GetName."] <".$nick->GetNick."> ".$message);

    # Match the first word (or at least the first letter) of the message
    # If it's a prechan it should match 100%, with all types of chars before and after the first word.
    # like [](){}- or whitespace or nothing
    # Need regex explanation? -> http://www.comp.leeds.ac.uk/Perl/matching.html
    my $match = $message ~~ m/^\W*(\w+)\W*/;

    # Put the word in the variable
    my $type = uc($1);
    #$self->PutModule($type);
    if ($match) {
        # Compare different types of announces,
        # assuming that there are common types like pre, (mod)nuke, unnuke, delpre, undelpre

        #PRE
        if ($type eq "PRE") {
            # Regex works for a lot of prechans but not for all.
            # Maybe you have to change this.
            # Order: PRE SECTION RELEASE
            $match = $message ~~ m/^\W*\w+\W+(\w+-?\w+)\W+(\w.+?)\W*$/;

            # Get Regex matches
            my $pretime = time();
            my $section = $1;
            my $release = $2;
            # Get Group from release
            $match = $release ~~ m/-(\w+)$/;
            my $group = $1;

            # DEBUG -> are all the matches correct?
            #$self->PutModule($type.": ".$section." > ".$release." - ".$group);

            # Add Pre
            $self->addPre($pretime, $release, $section, $group);
            $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG #pre :" . $message);
        # INFO
        } elsif ($type eq "INFO") {
            # Regex works for a lot of prechans but not for all.
            # Maybe you have to change this.
            # Order: INFO RELEASE 1 FILES 1 SIZE
	    $message =~ s/[[\]]//g;
	    my @array1 = split ' ',   $message;
	    #$self->PutModule("message: " . $message);
	    $match = $message ~~ m/^\W*\w+\W*(\w.+?)\W*(\d+\s\w+?)\W*(\d.+?)\W*$/;
            
	    # Get Regex Matches
            my $release = $array1[1];
            my $files = $array1[2];
	    $files =~ s/F//g;
            my $size = $array1[3];
	    $size =~ s/MB//g;

            # DEBUG -> are all the matches correct?
            $self->PutModule("Atype: " . $type. " release: ".$release." files: ".$files." - size:".$size);

            # Add Info
            $self->addInfo($release, $files, $size);
	    $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG #pre :" . $message);

        # NUKE
        } elsif ($type ~~ m/^(NUKE|MODNUKE)/) {
            my @array = split / /, $message;
    	    pop @array; # get rid of the last array element on right
    	    $message = join(' ', @array);
            
	    # Regex works for a lot of prechans but not for all.
            # Maybe you have to customize this.
            # Order: NUKE RELEASE REASON
            $match = $message ~~ m/^\W*\w+\W*(\w.+?)\W*(\w[\w|\.|-]*)\W*$/;
            # Get Regex Matches
            my $release = $1;
            my $reason = $2;

            # DEBUG -> are all the matches correct?
            $self->PutModule("tpye" . $type.":".$release." - ".$reason);

            # Nuke
            $self->changeStatus(1, $release, $reason);
	    $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG #pre :" . $message);
        # UNNUKE
        } elsif ($type eq "UNNUKE") {
            # Regex works for a lot of prechans but not for all.
            # Maybe you have to customize this.
            # Order: UNNUKE RELEASE REASON
            
            my @array = split / /, $message;
            pop @array; # get rid of the last array element on right
            $message = join(' ', @array);


	    $match = $message ~~ m/^\W*\w+\W*(\w.+?)\W*(\w[\w|\.|-]*)\W*$/;
            # Get Regex Matches
            my $release = $1;
            my $reason = $2;

            # DEBUG -> are all the matches correct?
            $self->PutModule("type ".$type.": ".$release." - ".$reason);

            # Unnuke
            $self->changeStatus(2, $release, $reason);
	    $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG #pre :" . $message);
        # DELPRE
        } elsif ($type eq "DELPRE") {
            # Regex works for a lot of prechans but not for all.
            # Maybe you have to customize this.
            # Order: DELPRE RELEASE REASON

            my @array = split / /, $message;
	    pop @array; # get rid of the last array element on right
            $message = join(' ', @array);


            $match = $message ~~ m/^\W*\w+\W*(\w.+?)\W*(\w[\w|\.|-]*)\W*$/;
            # Get Regex Matches
            my $release = $1;
            my $reason = $2;

            # DEBUG -> are all the matches correct?
            $self->PutModule($type.": ".$release." - ".$reason);

            # Delpre
            $self->changeStatus(3, $release, $reason);
 	    $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG #pre :" . $message);

        # UNDELPRE
        } elsif ($type eq "UNDELPRE") {
            # Regex works for a lot of prechans but not for all.
            # Maybe you have to customize this.
            # Order: UNDELPRE RELEASE REASON

            my @array = split / /, $message;
            pop @array; # get rid of the last array element on right
            $message = join(' ', @array);


            $match = $message ~~ m/^\W*\w+\W*(\w.+?)\W*(\w[\w|\.|-]*)\W*$/;
            # Get Regex Matches
            my $release = $1;
            my $reason = $2;

            # DEBUG -> are all the matches correct?
            $self->PutModule($type.": ".$release." - ".$reason);

            # Undelpre
            $self->changeStatus(4, $release, $reason);
            $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG #pre :" . $message);
        }
    }

    return $ZNC::CONTINUE;
}

##
# PreBot functions
##

# Add Pre
# Params (pretime, release, section, group)
sub addPre {
    my $self = shift;

    # get attribute values
    my ($pretime, $release, $section, $group) = @_;

    # DEBUG -> check if the variables are correct
    # $self->PutModule("Time: ".$pretime." - RLS: ".$release." - Section: ".$section." - Group: ".$group);

    # Connect to Database
    my $dbh = DBI->connect("DBI:mysql:database=$DB_NAME;host=$DB_HOST", $DB_USER, $DB_PASSWD)
        or die "Couldn't connect to database: " . DBI->errstr;

    # Set Query -> Add release
    my $query = "INSERT INTO ".$DB_TABLE." (`".$COL_PRETIME."`, `".$COL_RELEASE."`, `".$COL_SECTION."`, `".$COL_GROUP."`) VALUES( ?, ?, ?, ? );";

    # Execute Query
    $dbh->do($query, undef, $pretime, $release, $section, $group) or die $dbh->errstr;
    
    # Disconnect Database
    $dbh->disconnect();

    
}

# Info
# Params (release, files, size)
sub addInfo {
    my $self = shift;
    
    # get attribute values
    my ($release, $files, $size) = @_;

    # DEBUG -> check if the variables are correct
    # $self->PutModule(.$release." - Files: ".$files." - Size: ".$size);

    # Connect to Database
    my $dbh = DBI->connect("DBI:mysql:database=$DB_NAME;host=$DB_HOST", $DB_USER, $DB_PASSWD)
        or die "Couldn't connect to database: " . DBI->errstr;

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_FILES."` = ? , `".$COL_SIZE."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";

    # Execute Query
    $dbh->do($query, undef, $files, $size, $release) or die $dbh->errstr;

    # Disconnect Database
    $dbh->disconnect();
}

# Nuke, Unnuke, Delpre, Undelpre
# Params (status, release, reason)
sub changeStatus {
    my $self = shift;

    # get attribute values
    my ($status, $release, $reason) = @_;

    # DEBUG -> check if the variables are correct
    my $type;
    $type = "nuke" if ($status == 1);
    $type = "unnuke" if ($status == 2);
    $type = "delpre" if ($status == 3);
    $type = "undelpre" if ($status == 4);
    #$self->PutModule("Type: " .$type." - Release: ".$release." - Reason: ".$reason);

    # Connect to Database
    my $dbh = DBI->connect("DBI:mysql:database=$DB_NAME;host=$DB_HOST", $DB_USER, $DB_PASSWD)
        or die "Couldn't connect to database: " . DBI->errstr;

    # Set Query -> Change release status
    # 0:pre; 1:nuked; 2:unnuked; 3:delpred; 4:undelpred;
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_STATUS."` = ? , `".$COL_REASON."` = ? WHERE `".$COL_RELEASE."` LIKE ?;";
    
    #$self->PutModule($query);

    # Execute Query
    $dbh->do($query, undef, $status, $reason, $release) or die $dbh->errstr;
  
    #debug mysql
    ($sql_update_result) = $dbh->fetchrow;

    #$self->PutModule("WHAT: " . $sql_update_result);
    # Disconnect Database
    $dbh->disconnect();
}

1;
