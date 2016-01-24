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
my $COL_GENRE   = 'genre';       # genre of product
my $COL_URL     = 'url';         # productlink or something similiar
my $COL_MP3INFO = 'mp3info';     # mp3info
my $COL_VIDEOINFO = 'videoinfo'; # videoinfo

# If you want to do more advanced announce stuff, have a look at the announceX subs.
my $ANNOUNCE_NETWORK = 'puthereyournetworkname';
my $ANNOUNCE_CHANNEL = '#pre';
