#!/usr/bin/env perl

# os2ns.pl - OpenLDAP Schema to Netscape Schema converter and concatinator
#
# (c) 2017 Wayne State University
# This is a modified version of https://github.com/MI-OSiRIS/aa_services/blob/master/bin/os2ns.pl
# Modifications limited to file header comment
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use POSIX ':termios_h';
use File::Basename 'basename';
use Getopt::Long qw(GetOptions :config no_auto_abbrev no_ignore_case);
use utf8;

GetOptions(
    'd|ditch-blank-lines' => \my $ditch_blank_lines,
    'q|quiet' => \$ENV{OS2NS_QUIET},
    'h|help' => \my $help,
    'n|no-emoji' => \my $no_emoji,
    'ns-slapd' => \my $ns_slapd,
    'openldap-ldif' => \my $openldap_ldif,
);

our $VERSION = "0.01";

if (!$ARGV[1] || $help) {
    print usage();
    exit;
}

my $slaptest;
if ($openldap_ldif) {
    if ($slaptest = `which slaptest`) {
        chomp $slaptest;
    } else {
        die "[fatal] OpenLDAP must be installed in order to convert to OpenLDAP LDIF schema\n" .
            "        please check that it's installed and that 'slaptest' is in the \$PATH\n";
    }
}

# question, positive, negative chatacters.
my ($q_char, $p_char, $n_char, $ok_char) = ('?', '+', '-', 'OK');
if ($ENV{LANG} =~ /UTF\-8/i && !$no_emoji) {
    # we have a unicode-capable terminal why not use fun characters?
    # note the trailing spaces, these are wide characters.  digitally and graphically.
    binmode(STDOUT, ':utf8');
    binmode(STDERR, ':utf8');
    ($q_char, $p_char, $n_char, $ok_char) = ("🤔 ", "👍 ", "👎 ", "👌 ");
}

unless ($ENV{OS2NS_QUIET}) {
    print "\nOpenLDAP to LDIF Schema Converter v$VERSION\n";
    print "(c) 2017 Wayne State University\n\n";
}

my $outfile = $ARGV[$#ARGV];
my @files = @ARGV[0..$#ARGV-1];

if (-e $outfile) {
    unless ($ENV{OS2NS_QUIET}) {
        local $| = 1;
        print " [$q_char] The file '$outfile' already exists, overwrite? [y/N] ";
        
        # configure the terminal so we can do a blocking read of a single byte
        # from stdin
        my $t = POSIX::Termios->new();
        $t->getattr(fileno(STDIN));
        my $orig = $t->getlflag;
        $t->setlflag($orig & ~(ECHO | ECHOK | ICANON));
        $t->setcc(VTIME, 1);
        $t->setattr(fileno(STDIN), TCSANOW);
        
        # actually do the read of a single keystroke (byte)
        my $userin;
        sysread(STDIN, $userin, 1);
        
        # put things back the way they were
        $t->setlflag($orig);
        $t->setcc(VTIME, 0);
        $t->setattr(fileno(STDIN), TCSANOW);
        
        # print a newline for continuity / prettyness.
        print "\n";
        
        # N is the default so if anything but 'y' or 'Y' was entered
        # here, abort.
        if ($userin =~ /^y$/i) {
            print " [$p_char] User instructed to overwrite '$outfile'\n";
        } else {
            die " [$n_char] User aborted.\n\n";
        }
    }
}

my $invocation = "os2ns.pl "; 

# get the options right...
if ($ENV{OS2NS_QUIET}) {
    $invocation .= "-q ";
}
if ($ditch_blank_lines) {
    $invocation .= "-d ";
}
if ($no_emoji) {
    $invocation .= "-n ";
}

$invocation .= "@{[join(' ', map { basename($_) } @files)]} @{[basename($outfile)]}";

my $spaces = 75 - length($invocation);

unless ($spaces < 0) {
    $invocation = $invocation . (" " x ($spaces + 1)) . "#";
}

open my $ofh, '>', $outfile or die "Can't write to $outfile - $!\n";

print $ofh <<"EOF";
# Schema file compiled from OpenLDAP formatted file using os2ns.pl
# https://github.com/MI-OSiRIS/puppet-ds389/blob/master/files/tools/os2ns.pl
# Compiled @{[scalar localtime]}      

EOF

print $ofh "dn: cn=schema\n";
print $ofh "objectClass: top\n";
print $ofh "objectClass: ldapSubentry\n";
print $ofh "objectClass: subschema\n";
print $ofh "cn: schema\n";

my $ifh, $pdepth;
foreach my $file (@files) {
    if ($openldap_ldif) {
        my $time = time;
        my $conv_conf = "/tmp/schema_conv.$time.conf";
        my $conv_dir = "/tmp/ldif_conv_$time";
        open my $fh, '>', $conv_conf;
        print $fh "include $file\n";
        close $fh;
        mkdir $conv_dir;
        system($slaptest, '-f', $conv_conf, '-F', $conv_dir);        
    } else {
        open $ifh, '<', $file or die "Can't read from $file - $!\n";
        while (my $line = <$ifh>) {
            # any whitespace at the end of any line was just a newline.  plain and simple.
            $line =~ s/[\s\r\n]+$/\n/;
            
            if ($line =~ /^#/) {
                print $ofh $line;
            } elsif ($line =~ /^(attributeType)[\s\(\n]+/i) {
                $line =~ s/$1/attributeTypes:/;
                
                # make sure we have a space between the colon and the open paren
                if ($line =~ /attributeTypes:[\(\w]+/) {
                    $line =~ s/attributeTypes:/attributeTypes: /;
                }
                
                print $ofh $line;
            } elsif ($line =~ /(objectClass)[\s\(\n]+/i) {
                $line =~ s/$1/objectClasses:/;

                # make sure we have a space between the colon and the open paren
                if ($line =~ /objectClasses:[\(\w]+/) {
                    $line =~ s/objectClasses:/objectClasses: /;
                }

                print $ofh $line;
            } elsif ($line =~ /^\s*$/) {
                # no empty lines in LDIF, replace with comment lines.
                unless ($ditch_blank_lines) {
                    print $ofh "#\n";    
                }
            } elsif ($line =~ /^[\w\(\)\']+/) {
                # continuations need whitespace at the beginning
                print $ofh " " . $line;
            } else {
                # let's peek ahead to see if there's a lonesome paren on the next line..
                my $pos = tell($ifh);
                my $next_line = <$ifh>;
                if ($next_line =~ /^\s*(\(|\))[\r\n\s]*$/) {
                    # looks like it, we'll bring it up to this line and skip it.
                    my $paren = $1;
                    
                    $line =~ s/\n$//;
                    $line = "$line $paren";
                    
                    # check one more ...
                    $pos = tell($ifh);
                    $next_line = <$ifh>;
                    if ($next_line =~ /^\s*(\(|\))[\r\n\s]*$/) {
                        # wow, we're closing TWO parens, thats the most we can do in schema config,
                        # so this will be as deep as we go.  thank goodness i didn't have to write
                        # a proper parser.
                        $line = "$line $1";
                    } else {
                        # paren only went one deep, so seek back and let the next $line go through
                        # the works.
                        seek($ifh, $pos, 0);
                    }
        
                    print $ofh "$line\n";
                } else {
                    # seek back to where we were, the next line wasn't a lonesome paren.
                    seek($ifh, $pos, 0);
                    
                    # so just print it, there's nothing wrong with it!  hurrah!
                    print $ofh $line;
                }
            }
        }
    }
}

unless ($ENV{OS2NS_QUIET}) {
    print " [$ok_char] OpenLDAP configuration -> ldif ($outfile) conversion complete.\n\n";
}

sub usage {
    print <<"EOF";
Usage: os2ns.pl [options] <infile> <infile2> <infile..N> <outfile>

These options are available for 'os2ns.pl':
    -h, --help              Print this screen
    -q, --quiet             Do not print anything except errors, assume 'Y' to prompts
                            caution: WILL OVERWRITE WITHOUT WARNING
    -d, --ditch-blank-lines Don't preserve blank lines in OpenLDAP config with comment
                            lines.   Actual comment lines from OpenLDAP are preserved.
    -n, --no-emoji          Don't use emojis in the output, that's dumb.
        --ns-slapd          Convert to ns-slapd LDIF schema [default]
        --openldap-ldif     Convert to openldap-ldif schema (requires OpenLDAP be 
                            installed on this host)
    
EOF
}
