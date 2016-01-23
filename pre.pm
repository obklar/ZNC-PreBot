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

# DB Columns
my $COL_PRETIME = 'pretime';     # pre timestamp
my $COL_RELEASE = 'release';     # release name
my $COL_SECTION = 'section';     # section name
my $COL_FILES   = 'files';       # number of files
my $COL_SIZE    = 'size';        # release size
my $COL_STATUS  = 'status';      # 0:pre; 1:nuked; 2:unnuked; 3:delpred; 4:undelpred;
my $COL_REASON  = 'reason';      # reason for nuke/unnuke/delpre/undelpre
my $COL_NETWORK = 'network';     # network from which we got the nuke/whatever reason
my $COL_GROUP   = 'group';       # groupname
my $COL_GENRE   = 'genre';
my $COL_URL     = 'url';
my $COL_MP3INFO = 'mp3info';
my $COL_VIDEOINFO = 'videoinfo';

my $ANNOUNCE_NETWORK = 'criten';
my $ANNOUNCE_CHANNEL = '#pre-test';

# ONLY CHANGES THIS IF YOU KNOW WHAT YOU DO!
my %STATUSTYPES = ( "NUKE" => 1, "MODNUKE" => 1, "UNNUKE" => 2, "DELPRE" => 3, "UNDELPRE" => 4);

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

    # Split message into words (without dash)
    my @splitted_message = split / /, $message;

    # Check if message starts with a "!""
    my $match = substr($splitted_message[0], 0, 1) eq "!";

    if($match){
        # Get the type (it's the command), uppercased!
        $type = uc(substr($splitted_message[0], 1));
        # Compare different types of announces,
        # assuming that there are common types like pre, (mod)nuke, unnuke, delpre, undelpre

        # ADDPRE / SITEPRE
        if ($type eq "ADDPRE" || $type eq "SITEPRE") {
              # Regex works for a lot of prechans but not for all.
              # Maybe you have to change this.
              # Order: ADDPRE/SITEPRE RELEASE SECTION

              #Pretime is now
              my $pretime = time();

              my $release = $splitted_message[1];
              my $section = $splitted_message[2];


              my $group = getGroupFromRelease($release);

              # DEBUG -> are all the matches correct?
              $self->PutModule($type.": ".$section." > ".$release." - ".$group);

              # Add Pre
              $self->addPre($pretime, $release, $section, $group);
              # Announce Pre
              $self->announcePre($release, $section);

        # ADDOLD
        } elsif ($type eq "ADDOLD") {
              print $message;
              my $release = returnEmptyIfDash($splitted_message[1]);
              my $section = returnEmptyIfDash($splitted_message[2]);
              my $pretime = returnEmptyIfDash($splitted_message[3]);
              my $size    = returnEmptyIfDash($splitted_message[4]);
              my $files   = returnEmptyIfDash($splitted_message[5]);
              my $genre   = returnEmptyIfDash($splitted_message[6]);
              my $reason  = returnEmptyIfDash($splitted_message[7]);
              my $network = returnEmptyIfDash(join(' ',  splice(@splitted_message, 7))); # network contains maybe whitespaces, so we want everything to the end

              my $group = getGroupFromRelease($release);

              print "\nxxx$release\n";

              # DEBUG -> are all the matches correct?
              $self->PutModule("$type : $section - $release - $group - $pretime - $size - $files - $genre - $reason - $network");

              # Add Pre
              $self->addPre($pretime, $release, $section, $group);
              $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG ".$ANNOUNCE_CHANNEL." :" . $message);

              # Add Info
              $self->addInfo($release, $files, $size);

              # Add genre
              $self->addGenre($release, $genre);

              # Announce (we handle it like a pre, maybe you want to do it differently)
              $self->announcePre($release, $section);


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
        	    $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG ".$ANNOUNCE_CHANNEL." :" . $message);

        # GENRE
        } elsif ($type eq "GN") {
              my @array = split / /, $message;

              my $release = $array[1];
              my $genre   = $array[2];

              # DEBUG -> are all the matches correct?
              $self->PutModule("Genre: " . $type. " release: ".$release." genre: ".$genre);

              # Add Info
              $self->addGenre($release, $genre);
        	    $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG ".$ANNOUNCE_CHANNEL." :" . $message);

        # ADDURL
        } elsif ($type eq "ADDURL") {
              my @array = split / /, $message;

              my $release = $array[1];
              my $url   = $array[2];

              # DEBUG -> are all the matches correct?
              $self->PutModule("Url: " . $type. " release: ".$release." url: ".$url);

              # Add Info
              $self->addUrl($release, $url);
              $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG ".$ANNOUNCE_CHANNEL." :" . $message);

        # ADDMP3INFO
        } elsif( $type eq "MP3INFO") {
          my @array = split / /, $message;

          my $release = $array[1];
          my $mp3info   = $array[2];

          # DEBUG -> are all the matches correct?
          $self->PutModule("MP3Info: " . $type. " release: ".$release." mp3info: ".$mp3info);

          # Add Info
          $self->addMp3info($release, $mp3info);
          $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG ".$ANNOUNCE_CHANNEL." :" . $message);

        # ADDVIDEOINFO
        } elsif( $type eq "VIDEOINFO") {
          my @array = split / /, $message;

          my $release = $array[1];
          my $videoinfo   = $array[2];

          # DEBUG -> are all the matches correct?
          $self->PutModule("VideoInfo: " . $type. " release: ".$release." videoinfo: ".$videoinfo);

          # Add Info
          $self->addVideoinfo($release, $videoinfo);
          $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG ".$ANNOUNCE_CHANNEL." :" . $message);

        # NUKE/MODNUKE/UNNUKE/DELPRE/UNDELPRE (Status Change)
        } elsif (exists $STATUSTYPES{$type}) {
              # Order: NUKE RELEASE REASON NUKENET

              my $release = $splitted_message[1];
              my $reason = $splitted_message[2];
              my $network = $splitted_message[3];

              my $status = $STATUSTYPES{$type};

              # DEBUG -> are all the matches correct?
              $self->PutModule("tpye" . $type.":".$release." - ".$reason." network:".$network);
              # Nuke
              $self->changeStatus($release, $status, $reason, $network);

              # Announce Nuke
    	        $self->announceStatusChange($release, $type, $reason, $network);

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
    my $dbh = $self->getDBI();

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
    my $dbh = $self->getDBI();

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_FILES."` = ? , `".$COL_SIZE."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";
    # Execute Query
    $dbh->do($query, undef, $files, $size, $release) or die $dbh->errstr;
    # Disconnect Database
    $dbh->disconnect();
}

# Genre
# Params (release, genre)
sub addGenre {
    my $self = shift;

    # get attribute values
    my ($release, $genre) = @_;
    # DEBUG -> check if the variables are correct
    # $self->PutModule(.$release." - Files: ".$files." - Size: ".$size);
    # Connect to Database
    my $dbh = $self->getDBI();
sub getGroupFromRelease {
  $match = $1 ~~ m/-(\w+)$/;
  return $1;
}

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_GENRE."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";
    print "\nzzz$query\n";
    # Execute Query
    $dbh->do($query, undef, $genre, $release) or die $dbh->errstr;
    # Disconnect Database
    $dbh->disconnect();
}
# Url
# Params (release, url)
sub addUrl {
    my $self = shift;

    # get attribute values
    my ($release, $url) = @_;
    # DEBUG -> check if the variables are correct
    # $self->PutModule(.$release." - Files: ".$files." - Size: ".$size);
    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_URL."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";
    print "\nzzz$query\n";
    # Execute Query
    $dbh->do($query, undef, $url, $release) or die $dbh->errstr;
    # Disconnect Database
    $dbh->disconnect();
}

# Mp3info
# Params (release, mp3info)
sub addMp3info {
    my $self = shift;

    # get attribute values
    my ($release, $mp3info) = @_;
    # DEBUG -> check if the variables are correct
    # $self->PutModule(.$release." - Files: ".$files." - Size: ".$size);
    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_MP3INFO."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";
    print "\nzzz$query\n";
    # Execute Query
    $dbh->do($query, undef, $mp3info, $release) or die $dbh->errstr;
    # Disconnect Database
    $dbh->disconnect();
}

# Videoinfo
# Params (release, mp3info)
sub addVideoinfo {
    my $self = shift;

    # get attribute values
    my ($release, $videoinfo) = @_;
    # DEBUG -> check if the variables are correct
    # $self->PutModule(.$release." - Files: ".$files." - Size: ".$size);
    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_VIDEOINFO."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";
    print "\nzzz$query\n";
    # Execute Query
    $dbh->do($query, undef, $videoinfo, $release) or die $dbh->errstr;
    # Disconnect Database
    $dbh->disconnect();
}

# Nuke, Unnuke, Delpre, Undelpre
# Params (release, status, reason, network)
sub changeStatus {
    my $self = shift;
    # get attribute values
    my ($release, $status, $reason , $network) = @_;
    # DEBUG -> check if the variables are correct
    #$self->PutModule("Type: " .$type." - Release: ".$release." - Reason: ".$reason);

    my $type = $self->statusToType($status);
    $self->PutModule("$type $release - Reason: $reason ($network)");

    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Change release status
    # 0:pre; 1:nuked; 2:unnuked; 3:delpred; 4:undelpred;
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_STATUS."` = ? , `".$COL_REASON."` = ?, `".$COL_NETWORK."` = ? WHERE `".$COL_RELEASE."` LIKE ?;";

    #$self->PutModule($query);
    # Execute Query
    $dbh->do($query, undef, $status, $reason, $network, $release) or die $dbh->errstr;

    #debug mysql
    #($sql_update_result) = $dbh->fetchrow;
    #$self->PutModule("WHAT: " . $sql_update_result);
    # Disconnect Database
    $dbh->disconnect();
}


# Returns empty string if $1 is a dash ("-")
# Params: (string)
sub returnEmptyIfDash {
  $str = shift;
  print "$str\n";
  if($str eq "-"){
    return "";
  }

  return $str;
}

# Get a database connection
sub getDBI {
  return DBI->connect("DBI:mysql:database=$DB_NAME;host=$DB_HOST", $DB_USER, $DB_PASSWD) or die "Couldn't connect to database: " . DBI->errstr;
}

# Extract the groupname of a release/dirname
# Params: (release)
sub getGroupFromRelease {
  my $release = shift;
  return substr($release, rindex($release, "-")+1);
}

#announce a pre
# Params: (release, section)
sub announcePre {
  my $self = shift;
  my ($release, $section) = @_;
  $self->sendAnnounceMessage("[PRE] [$section] - $release");

}

#announce a status Change
# Params: (release, status, reason, network)
sub announceStatusChange {
  my $self = shift;
  my ($release, $type, $reason, $network) = @_;
  $self->sendAnnounceMessage("[$type] - $release - $reason - $network");
}

# Send a message to announce channel
# Params: (message)
sub sendAnnounceMessage {
  my $self = shift;
  my $message = shift;
  $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG ".$ANNOUNCE_CHANNEL." :".$message);
}

# Convert Status (integer) to String (type)
# Params: (status)
# Return: Type (String)
sub statusToType {
  my $status = shift;
  my %rstatustypes = reverse %STATUSTYPES;
  return $rstatustypes{$status};
}

# Convert Status (integer) to String (type)
# Params: (status)
# Return: Type (String)
sub typeToStatus {
  my $type = shift;
  return $STATUSTYPES{$type};
}

1;
