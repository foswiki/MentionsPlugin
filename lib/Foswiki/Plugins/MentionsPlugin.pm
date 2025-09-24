# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# MentionsPlugin is Copyright (C) 2021-2025 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::MentionsPlugin;

=begin TML

---+ package Foswiki::Plugins::MentionsPlugin

base class to hook into the foswiki core

=cut

use strict;
use warnings;

use Foswiki::Func ();

our $VERSION = '1.30';
our $RELEASE = '%$RELEASE%';
our $SHORTDESCRIPTION = 'Mentions for Foswiki';
our $LICENSECODE = '%$LICENSECODE%';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

=begin TML

---++ initPlugin($topic, $web, $user) -> $boolean

initialize the plugin, automatically called during the core initialization process

=cut

sub initPlugin {

  Foswiki::Func::registerTagHandler('MENTIONS', sub { return getCore()->MENTIONS(@_); });

  if (Foswiki::Func::getContext()->{command_line}) {
    Foswiki::Func::registerRESTHandler('importData', sub { return getCore()->restImportData(@_); },
      validate => 1,
      authenticate => 1,
      http_allow => 'GET,POST',
    );

    Foswiki::Func::registerRESTHandler('checkData', sub { return getCore()->restCheckData(@_); },
      validate => 1,
      authenticate => 1,
      http_allow => 'GET,POST',
    );
  }

  return 1;
}

=begin TML

---++ getCore() -> $core

returns a singleton Foswiki::Plugins::MentionsPlugin::Core object; a new core is allocated 
during each session request; once a core has been created it is destroyed during =finishPlugin()=

=cut

sub getCore {
  unless (defined $core) {
    require Foswiki::Plugins::MentionsPlugin::Core;
    $core = Foswiki::Plugins::MentionsPlugin::Core->new();
  }
  return $core;
}

=begin TML

---++ finishPlugin

finish the plugin and the core if it has been used,
automatically called during the core initialization process

=cut

sub finishPlugin {
  $core->finish() if defined $core;
  undef $core;
}

=begin TML

---++ ObjectMethod preRenderingHandler($text)

renders @ links pointing to user profile pages

=cut

sub preRenderingHandler {
  getCore()->preRenderingHandler($_[0]);
}

=begin TML

---++ ObjectMethod afterSaveHandler($text, $topic, $web, $error, $meta )

=cut

sub afterSaveHandler {
  getCore()->afterSaveHandler(@_);
}

=begin TML

---++ ObjectMethod afterRenameHandler( $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment )

=cut

sub afterRenameHandler {
  getCore->afterRenameHandler(@_);
}

1;
