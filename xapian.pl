#!/usr/bin/perl

# ----- BEGIN LICENSE BLOCK ----- //
#
# (c) Copyright 2018, Tsert Inc., All Rights Reserved.
#
# Tsert Inc. MAKES NO REPRESENTATIONS AND EXTENDS NO WARRANTIES, EXPRESS OR
# IMPLIED, WITH RESPECT TO THE SOFTWARE, INCLUDING, BUT NOT LIMITED TO,
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR ANY PARTICULAR
# PURPOSE, AND THE WARRANTY AGAINST INFRINGEMENT OF PATENTS OR OTHER
# INTELLECTUAL PROPERTY RIGHTS. THE SOFTWARE IS PROVIDED "AS IS", AND IN NO
# EVENT SHALL Tsert Inc. OR ANY OF ITS AFFILIATES BE LIABLE FOR ANY DAMAGES,
# INCLUDING ANY LOST PROFITS OR OTHER INCIDENTAL OR CONSEQUENTIAL DAMAGES
# RELATING TO THE USE OF THIS SOFTWARE.
#
# Protection of Tsert Inc. Systems Software and Data Files.
#
# Except as expressly authorized by Tsert Inc., you may not (i) disassemble,
# decompile or otherwise reverse engineer Tsert Inc. systems software, or
# (ii) create derivative works based upon Tsert Inc. systems software and
# data files, or (iii) rent, lease, sublicense, distribute, transfer, copy,
# reproduce, modify or timeshare Tsert Inc. systems software amd data files,
# or (iv) allow any third party to access or use Tsert Inc. systems software
# and data files, or (v) modify Tsert Inc. systems software or data files,
# including any deletion of code from or addition of code to the software
# and any modification to the data files.
#
# ----- END LICENSE BLOCK ----- //
#
# Author Pierre Innocent <dev@breezeos.com>
# Copyright (C) Tsert Inc., All rights reserved.
# Version 0.9.0
#
use strict;
use warnings;
use Data::Dumper qw(Dumper);

use IO::Easy;
use IO::Easy::Dir;
use IO::Easy::File;
use File::MimeInfo;
use Cwd;

use Search::Xapian;
use Search::Xapian::Document;
use Search::Xapian::Database;
use Search::Xapian::QueryParser;
use Search::Xapian::WritableDatabase;
 
our $USER = getpwuid( $< );

our $EXTENSIONS = "^(txt|csv|html|png|jpg|jpeg|gif|svg|xpm|mov|avi|mkv|doc|htm)\$";
our $MMEDIA = "^(png|jpg|jpeg|gif|svg|xpm|mov|avi|mkv)\$";

our	$DB = undef;
our	$QP = undef;
our	$STEMMER = undef;
our $MAXHITS = 250;

sub open_write_db {
	my $user = shift;
	my $dbpath = "/var/lib/brzidx/xapian/${user}.db"

	$DB = Search::Xapian::WritableDatabase->new(
		$dbpath, Search::Xapian::DB_CREATE_OR_OPEN
	);
};

sub open_read_db {
	my $user = shift;
	my $dbpath = "/var/lib/brzidx/xapian/${user}.db"

	$DB = Search::Xapian::Database->new( $dbpath );
	$QP = new Search::Xapian::QueryParser($DB);
};

sub search_db {

	my $query = shift;
	my $extended = shift;
	my $enq = undef;

	if (defined($extended)) {
		$QP->set_stemmer(new Search::Xapian::Stem("english"));
		$QP->set_default_op(Search::Xapian::OP_AND);
		$enq = $DB->enquire(
			$QP->parse_query(
				$query,
				Search::Xapian::FLAG_BOOLEAN|
				Search::Xapian::FLAG_LOVEHATE|
				Search::Xapian::FLAG_PURE_NOT|
				Search::Xapian::FLAG_BOOLEAN_ANY_CASE
			)
		);
	} else {
		$enq = $DB->enquire( $query );
	}

	printf "Running query '%s'\n", $enq->get_query()->get_description();

	my @matches = $enq->matches(0, $MAXHITS);

	print scalar(@matches) . " results found\n";

	my $hits = scalar(@matches);

	foreach my $match ( @matches ) {
		my $doc = $match->get_document();
		printf "ID %d %d%% [ %s ]\n", $match->get_docid(), $match->get_percent(), $doc->get_data();
	}
};

my $xapian_handler = sub {

	my $entry = shift;

	if (not defined( $entry  )) { return 0; }

	print "[0;33mTrying to process path ", $entry->path, " ...[0m\n";

	return 0 if $entry->type eq 'dir' and $entry->name =~ /^(CVS|.git)$/;
	return 0 if $entry->type ne 'dir' and not $entry->extension =~ m/$EXTENSIONS/;
	return 0 if $entry->size > 1024000;

	print "[0;34mProcessing path ", $entry->path, "...[0m\n";

	if (! defined( $USER ) || $USER eq '') {
		print "[0;34mMust specify a user name ![0m\n";
		return 0
	}

	if ($entry->type ne 'dir') {
		#$entry->enc = "utf-8";

		if ($entry->extension =~ m/$MMEDIA/) {
			indexing( $USER, $entry );
		} else {
			indexing( $USER, $entry, "true" );
		}
	}

	return 1;
};

#sub index_dir() {
#	opendir(D, "$folder") || die "Can't open directory $folder: $!\n";
#	my @list = grep !/^\.\.?$/, readdir(D);
#	closedir(D);
#
#	foreach my $f (@list) {
#		print "\$f = $f\n";
#		indexing( $user, $f );
#	}
#};

sub index_dir {
	my $folder = shift;
	my $io = IO::Easy->new($folder);
	my $dir = $io->as_dir;
	print "Scanning path ", $folder, " ...\n";
	$dir->scan_tree($xapian_handler);
};

sub indexing {

	my $user = shift;
	my $entry = shift;
	my $scan_contents = shift;
	my $pathspec = $entry->path;

	print "Indexing path ", $entry->path, " ...\n";

	my $doc = new Search::Xapian::Document();
	my $tg = new Search::Xapian::TermGenerator();

	$pathspec =~ s/[\/\.-]/ /g;
	$doc->set_data( $entry->path );

	$tg->set_stemmer(new Search::Xapian::Stem("english"));
	$tg->set_document($doc);
	$tg->index_text( $pathspec );
	#$tg->index_text( $meta );

	if (defined( $scan_contents )) {
		$tg->index_text( $entry->contents );
	}

	$DB->add_document( $doc );
};

our $dosearch = undef;
our $doindex = undef;
our $option = undef;
our $value = undef;
our $extended = undef;

#foreach my $idx (0 .. $#ARGV)

foreach my $arg (@ARGV) {

	if ($arg =~ m/^[-]+[a-z]*/) {
		if ($arg =~ m/^[-]+(search)$/) {
			$dosearch = "yes";
			open_read_db( $USER );
		} elsif ($arg =~ m/^[-]+(index)$/) {
			$doindex = "yes";
			open_write_db( $USER );
		} elsif ($arg =~ m/^[-]+(extended)$/) {
			$extended = "yes";
		} elsif ($arg =~ m/^[-]+(user|stemmer|maxhits)$/) {
			$option = $arg;
		} else {
			printf "Invalid option ${arg} !\n";
			exit(1);
		}
	} else {

		if (defined( $option ) && $option eq "--user") {
			$USER = $arg;
		} elsif (defined( $option ) && $option eq "--stemmer") {
			$STEMMER = $arg;
		} elsif (defined( $option ) && $option eq "--maxhits") {
			$MAXHITS = $arg;
		} elsif (defined( $doindex ) and not defined( $dosearch )) {
			index_dir( "$arg" );
		} elsif (defined( $dosearch ) and not defined( $doindex )) {
			search_db( $arg, $extended );
		}

		undef $option;
	}
};

if (defined( $DB )) {
	$DB->close();
}

