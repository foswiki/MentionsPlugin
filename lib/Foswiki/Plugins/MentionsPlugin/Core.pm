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

package Foswiki::Plugins::MentionsPlugin::Core;

=begin TML

---+ package Foswiki::Plugins::MentionsPlugin::Core

Core of the plugin. There can only be one.

=cut

use strict;
use warnings;

use Foswiki::Meta ();
use Foswiki::Func ();
use Foswiki::Time ();
use Foswiki::Plugins ();
use Foswiki::DBI ();
use Foswiki::Sandbox ();
use Foswiki::Iterator::DBIterator ();
use Error qw(:try);
use Digest::MD5 ();
use Encode ();

#use Data::Dump qw(dump); # disable on production

my $STARTTOKEN = qr/^|(?<=[^[:alpha:][:digit:]])/m;
my $ENDTOKEN   = qr/$|(?=[^[:alpha:][:digit:]])/m;

=begin TML

---++ ClassMethod new() -> $core

constructor for a Core object

=cut

sub new {
  my $class = shift;

  my $this = bless({
    emailNotification => $Foswiki::cfg{MentionsPlugin}{EmailNotification} // 1,
    excludeWeb => $Foswiki::cfg{MentionsPlugin}{ExcludeWeb} // '^(System|Applications([\./].*)?|(.*[\./])?Trash([\./].*)?)$',
    excludeTopic => $Foswiki::cfg{MentionsPlugin}{ExcludeTopic} // '^(WebAtom|WebRss|WebSearch.*|WebChanges|WebStatistics|WebNotify|WebTopicList|WebIndex|WebLeftBar|WebSideBar|WebPreferences|TrashAttachment|WebLeftBar.*)$',
    excludeWikiUser => $Foswiki::cfg{MentionsPlugin}{ExcludeWikiUser} // '^(AdminUser)$',
    debug => $Foswiki::cfg{MentionsPlugin}{Debug} // 0,
    mode => $Foswiki::cfg{MentionsPlugin}{Mode} // 'all',
    mentionsFormat => $Foswiki::cfg{MentionsPlugin}{MentionsFormat} // '<a href="%url%" class="mention %class%">%title%</a>',
    @_
  }, $class);

  return $this;
}

=begin TML

---++ ObjectMethod finish()

called when this object is destroyed

=cut

sub finish {
  my $this = shift;

  undef $this->{_db};
  undef $this->{_templates};
  undef $this->{_doneLoadTemplate};
  undef $this->{_mentionsOfTopic};
}

=begin TML

---++ ObjectMethod db() -> $database

returns a Foswiki::DBI::Database object that we talk to.

=cut

sub db {
  my $this = shift;

  $this->{_db} = Foswiki::DBI::loadSchema("Foswiki::Plugins::MentionsPlugin::Schema")
    unless $this->{_db};

  return $this->{_db};
}

=begin TML

---++ ObjectMethod preRenderingHandler($text)

renders the @ links to user profile pages

=cut

sub preRenderingHandler {
  my $this = shift;

  $_[0] =~ s/$STARTTOKEN\@($Foswiki::regex{wikiWordRegex})$ENDTOKEN/$this->formatMention($1)/ge;
}

=begin TML

---++ ObjectMethod formatMention($wikiName) -> $string

renders the @ link for a given wikiName

=cut

sub formatMention {
  my ($this, $wikiName) = @_;

  my $web = $Foswiki::cfg{UsersWebName};

  return "@".$wikiName
    unless Foswiki::Func::topicExists($web, $wikiName);

  my $title = Foswiki::Func::getTopicTitle($web, $wikiName);
  my $class = Foswiki::Func::getCanonicalUserID($wikiName) ? "jqUserTooltip" : "foswikiAlert";
  my $url = Foswiki::Func::getScriptUrlPath($web, $wikiName, "view");

  my $format = $this->{mentionsFormat};
  $format =~ s/\%url%/$url/g;
  $format =~ s/\%class%/$class/g;
  $format =~ s/\%title%/$title/g;

  return $format;
}

=begin TML

---++ ObjectMethod MENTIONS($session, $params, $topic, $web)

handler for the =%MENTIONS= macro

=cut

sub MENTIONS {
  my ($this, $session, $params, $topic, $web) = @_;

  $this->writeDebug("called MENTIONS()");

  my %opts = ();

  my $theWeb = $params->{web} // $web;
  my $theTopic = $params->{topic} // $topic;

  if ($theWeb && $theWeb eq '*') {
    $theWeb = undef;
  } else {
    $theWeb = Foswiki::Sandbox::validateTopicName($theWeb)
  }

  if ($theTopic && $theTopic eq '*') {
    $theTopic = undef;
  } else {
    $theTopic = Foswiki::Sandbox::validateTopicName($theTopic)
  }

  ($theWeb, $theTopic) = Foswiki::Func::normalizeWebTopicName($theWeb, $theTopic)
    if $theWeb && $theTopic;

  $theWeb =~ s/\//./g if defined $theWeb;

  $opts{web} = $theWeb if $theWeb;
  $opts{topic} = $theTopic if $theTopic;

  my $wikiName = $params->{wikiname};
  if ($wikiName && $wikiName eq '*') {
    $wikiName = undef;
  } else {
    $wikiName = _sanitizeString($wikiName);
  }
  $opts{wikiName} = $wikiName if $wikiName;

  my $self = Foswiki::Func::getWikiName();
  my $by = $params->{by} // $self;

  if ($by eq '*') {
    $by = undef;
  } else {
    $by = _sanitizeString($by);
  }
  $opts{mentionedBy} = $by if $by;

  my $from = _parseTime($params->{since} // $params->{from});
  my $to = _parseTime($params->{until} // $params->{to});
  $opts{from} = $from if $from;
  $opts{to} = $to if $to;

  $this->writeDebug("... web=".($theWeb//'undef').", topic=".($theTopic//'undef').", wikiName=".($wikiName//'undef').", by=".($by//'undef').", from=".($from//'undef').", to=".($to//'undef'));

  $opts{order} = _sanitizeString($params->{sort}) // "date";
  $opts{order} .= " desc" if Foswiki::Func::isTrue($params->{reverse}, 0);

  my $it;
  my $error;
  try {
    $it = $this->eachMention(%opts);
  } catch Error with {
    $error = shift;
    $error =~ s/ at .*$//;
  };
  return _inlineError($error) if defined $error;

  my @result = ();
  my $index = 0;
  my $count = 0;
  while ($it->hasNext) {
    my $row = $it->next();
    $index++;

    next if defined($params->{skip}) && $index <= $params->{skip};
    next unless Foswiki::Func::checkAccessPermission("VIEW", $self, undef, $row->{topic}, $row->{web});

    #$this->writeDebug("found row".dump($row));
 
    my $line = $params->{format} // '$wikiName was mentioned in [[$web.$topic]] by $by at $formatTime($date) <br/>';
    $line =~ s/\$index\b/$index/g;
    $line =~ s/\$wikiName\b/$row->{wikiName}/g;
    $line =~ s/\$by\b/$row->{mentionedBy}/g;
    $line =~ s/\$web\b/$row->{web}/g;
    $line =~ s/\$topic\b/$row->{topic}/g;
    $line =~ s/\$part\b/$row->{part}/g;
    $line =~ s/\$date\b/$row->{date}/g;
    $line =~ s/\$fingerPrint\b/$row->{fingerPrint}/g;
    $line =~ s/\$formatTime\((\d+?)(?:, *(.*?))?\)/_formatTime($1, $2)/ge;
 
    push @result, $line if $line ne "";
    $count++;

    last if defined($params->{limit}) && $count >= $params->{limit};
  }
  return "" unless @result;
 
  my $result = Foswiki::Func::decodeFormatTokens(($params->{header} // '') .join($params->{separator} // '', @result) . ($params->{footer} // ''));

  $result =~ s/\$count\b/$count/g;
  
  return $result;
}

=begin TML

---++ ObjectMethod afterRenameHandler($oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment)

this handler makes sure entries in the mentions database are renamed properly when a topic is moved.

=cut

sub afterRenameHandler {
  my ($this, $oldWeb, $oldTopic, $oldAttachment, $newWeb, $newTopic, $newAttachment ) = @_;

  $this->writeDebug("called afterRenameWeb");

  $oldWeb =~ s/\//./g;
  $newWeb =~ s/\//./g;

  $this->writeDebug("old=$oldWeb.$oldTopic, new=$newWeb, $newTopic");

  $this->moveMentions($oldWeb, $oldTopic, $newWeb, $newTopic);
}

=begin TML

---++ ObjectMethod afterSaveHandler($text, $topic, $web, $meta)

this handler analyses the text being saved. any mentioning in there will create a notification.

=cut

sub afterSaveHandler {
  my ($this, $text, $topic, $web, $meta) = @_;

  #$this->writeDebug("called afterSaveHandler");
  $web =~ s/\//./g;

  my $mode = Foswiki::Func::getPreferencesValue("MENTIONSPLUGIN_MODE") || $this->{mode};

  my $mentions = $this->updateTopic($web, $topic, $meta, $mode);

  my $doNotify = Foswiki::Func::getPreferencesValue("MENTIONSPLUGIN_NOTIFICATION");
  if (defined $doNotify && $doNotify ne "") {
    $doNotify = Foswiki::Func::isTrue($doNotify);
  } else {
    $doNotify = $this->{emailNotification};
  }

  my $doNotifySelf = Foswiki::Func::getPreferencesFlag("MENTIONSPLUGIN_NOTIFYSELF");

  if ($doNotify) {
    my $self = Foswiki::Func::getWikiName();
    if (!$doNotifySelf && $self =~ /$this->{excludeWikiUser}/) {
      $this->writeDebug("not sending mentions by $self"); 
    } else {
      foreach my $record (@$mentions) {

        $this->writeDebug("found new mention of $record->{wikiName} in $record->{part} of $web.$topic");

        if (!$doNotifySelf && $record->{wikiName} eq $self) {
          $this->writeDebug("not sending notifications to oneself");
          next;
        }

        if ($record->{wikiName} =~ /$this->{excludeWikiUser}/) {
          $this->writeDebug("not sending notifications to $record->{wikiName}");
          next;
        }

        $this->sendNotification($record, $web, $topic, $meta)
      }
    }
  } else {
    $this->writeDebug("sending notifications has been disabled");
  }
}

=begin TML

---++ ObjectMethod sendNotification($record, $web, $topic, $meta)

sends an email notification to the wikiName user

=cut

sub sendNotification {
  my ($this, $record, $web, $topic, $meta) = @_;

  $this->writeDebug("called sendNotification($record->{wikiName}, $web, $topic)");
  if ($this->{_blockNotifications}) {
    $this->writeDebug("... notifications blocked");
    return;
  }

  my @emails = Foswiki::Func::wikinameToEmails($record->{wikiName});

  if (@emails && $emails[0]) {
    $this->writeDebug("... emails=@emails");
  } else {
    $this->writeDebug("... no emails found for $record->{wikiName}");
    return;
  }

  my $context = Foswiki::Func::getContext();
  $context->{has_fragment} = 1 if $record->{fragment} ne "";

  my $tmpl = $this->getTemplate();

  my $wikiName = Foswiki::Func::getWikiName();
  Foswiki::Func::setPreferencesValue("MENTION", $record->{wikiName});
  Foswiki::Func::setPreferencesValue("MENTIONED_BY", $wikiName);
  Foswiki::Func::setPreferencesValue("MENTIONED_PART", $record->{part});
  Foswiki::Func::setPreferencesValue("MENTIONED_FRAGMENT", $record->{fragment});
  Foswiki::Func::setPreferencesValue("MENTION_EMAIL", $emails[0]);

  my $text = $tmpl;
  $text = Foswiki::Func::expandCommonVariables($text, $topic, $web, $meta) if $text =~ /%/;
  $text =~ s/^\s+//g;
  $text =~ s/\s+$//g;

  delete $context->{mentioned_sentence};


  #$this->writeDebug("...email text=\n<<<\n$text\n>>>>");

  Foswiki::Func::writeEvent("sendmail", "to=$emails[0] subject=mentioned");
  my $errors = Foswiki::Func::sendEmail($text, 3);
 
  if ($errors) {
    Foswiki::Func::writeWarning("Failed to send mails: $errors");
    $this->writeDebug("Failed to send mails: $errors");
  } else {
    $this->writeDebug("... sent email successfully");
  }
 
  return $errors;
}

=begin TML

---++ ObjectMethod getTemplate($name)

returns the content of the named template, defaulting to the =mentions::notify= template
if =$name= is undefined.

=cut

sub getTemplate {
  my ($this, $name) = @_;

  $name ||= 'mentions::notify';

  my $tmpl = $this->{_templates}{$name};

  unless (defined $tmpl) {
    unless ($this->{_doneLoadTemplate}) {
      Foswiki::Func::loadTemplate("mentionsplugin");
      $this->{_doneLoadTemplate} = 1;
    }

    $tmpl = $this->{_templates}{$name} = Foswiki::Func::expandTemplate($name);
    $this->writeDebug("... woops, empty template for $name") unless $tmpl;
  }

  return $tmpl;
}

=begin TML

---++ ObjectMethod restCheckData($session)

this is handling the "checkData" REST handler. it verifies that each mentioning in the
database is actually referring to an existing user and topic. Parameters:

   * debug: switch on/off debugging output
   * dry: run in dry mode, i.e. don't alter the database

=cut

sub restCheckData {
  my ($this, $session) = @_;

  my $request = Foswiki::Func::getRequestObject();

  my $debug = $request->param("debug");
  $this->{debug} = Foswiki::Func::isTrue($debug) if defined $debug;

  $this->writeDebug("called restCheckData()");
  throw Error::Simple("not allowed") unless Foswiki::Func::getContext()->{isadmin};

  my $isDry = Foswiki::Func::isTrue($request->param("dry"), 0);

  my $count = 0;

  my $it = $this->eachMention();
  while ($it->hasNext) {
    my $row = $it->next();

    my $web = $row->{web};
    my $topic = $row->{topic};
    if (defined($web) && defined($topic) && !Foswiki::Func::topicExists($web, $topic)) {
      $this->writeDebug("topic does not exist anymore: $web.$topic");
      $count += $this->deleteMentions(web => $web, topic => $topic) unless $isDry;
      next;
    }

    my $wikiName = $row->{wikiName};
    if (defined($wikiName)) {

      # wikiName does not exist anymore
      if (!Foswiki::Func::getCanonicalUserID($wikiName)) {
        $this->writeDebug("user $wikiName isn't known anymore ... deleting mentions");
        $count += $this->deleteMentions(wikiName => $wikiName) unless $isDry;
        next;
      }
      if (Foswiki::Func::isGroup($wikiName)) {
        $this->writeDebug("$wikiName is a group ... deleting mentions");
        $count += $this->deleteMentions(wikiName => $wikiName) unless $isDry;
        next;
      }
    }

    my $by = $row->{mentionedBy};
    if (defined($by) && !Foswiki::Func::getCanonicalUserID($by)) {
      $this->writeDebug("mentioner $by isn't known anymore ... deleting mentions");
      $count += $this->deleteMentions(mentionedBy => $by) unless $isDry;
      next;
    }
  }

  $this->writeDebug("deleted $count records".($isDry?" (DRY)":""));

  return "";
}

=begin TML

---++ ObjectMethod restImportData()

this is handling the "importData" REST handler. it crawls all of the wiki
and populates the database with the found mentionings. There are a couple of 
parameters:

   * debug: switch on/off debugging output
   * dry: switch on/off dry mode, ie. don't insert any data into the database
   * web or webs: explicit list of webs to crawl
   * includeweb: regex of webs to crawl
   * excludeweb: regex of webs not to crawl
   * includetopic: regex of topics to crawl
   * excludetopic: regex of topics not to crawl

=cut

sub restImportData {
  my ($this, $session) = @_;

  my $request = Foswiki::Func::getRequestObject();

  my $debug = $request->param("debug");
  $this->{debug} = Foswiki::Func::isTrue($debug) if defined $debug;

  $this->writeDebug("called restImportData()");
  throw Error::Simple("not allowed") unless Foswiki::Func::getContext()->{isadmin};

  my $isDry = Foswiki::Func::isTrue($request->param("dry"), 0);
  my $doDelete = Foswiki::Func::isTrue($request->param("delete"), 0);

  if ($doDelete) {
    my $numDeleted = $isDry ? 0 : $this->deleteMentions();
    $this->writeDebug("deleted $numDeleted old record(s)");
  }

  my $includeWeb = $request->param("includeweb");
  my $excludeWeb = $request->param("excludeweb") // $this->{excludeWeb};

  my @webs = split(/\s*,\s*/, $request->param("web") // $request->param("webs") // '');
  @webs = Foswiki::Func::getListOfWebs( "user,public" ) unless @webs;

  if ($includeWeb) {
    $includeWeb =~ s/,/|/g;
    @webs = grep {/$includeWeb/} @webs;
  }

  if ($excludeWeb) {
    $excludeWeb =~ s/,/|/g;
    @webs = grep {!/$excludeWeb/} @webs;
  }

  my $includeTopic = $request->param("includetopic");
  my $excludeTopic = $request->param("excludetopic") // $this->{excludeTopic};

  $includeTopic =~ s/,/|/g if $includeTopic;
  $excludeTopic =~ s/,/|/g if $excludeTopic;

  my $count = 0;
  foreach my $web (@webs) {
    $this->writeDebug("processing web $web");
    my $webObject = Foswiki::Meta->new($session, $web );
    my $it = $webObject->eachTopic();
    while ($it->hasNext) {
      my $topic = $it->next();
      next if $includeTopic && $topic !~ /$includeTopic/;
      next if $excludeTopic && $topic =~ /$excludeTopic/;
      my $mentions = $this->updateTopic($web, $topic, undef, $isDry);
      $count += scalar(@$mentions);
    }
  }

  my $quiet = Foswiki::Func::isTrue($request->param("quiet"), 0);

  return "" if $quiet;
  return ($isDry?"would have ":"")."added $count new mention(s)\n\n";
}

=begin TML

---++ ObjectMethod updateTopic($web, $topic, $meta, $mode, $isDry) -> $mentions

reads a single topic and updates the mentioning database, returns
a hash ref to new mentions found, keyed by their finger print

=cut

sub updateTopic {
  my ($this, $web, $topic, $meta, $mode, $isDry) = @_;

  $mode //= $this->{mode};

  $web =~ s/\//./g;
  return if $web =~ /$this->{excludeWeb}/ || $topic =~ /$this->{excludeTopic}/;

  #$this->writeDebug("called updateTopic($web.$topic)");

  ($meta) = Foswiki::Func::readTopic($web, $topic) unless defined $meta;
  my $revInfo = $meta->getRevisionInfo();
  my $mentionedBy = Foswiki::Func::getWikiName($revInfo->{author}) // $revInfo->{author};
  my $mentions = $this->extractMentions($meta, $mode);
  my @newMentions = ();

  foreach my $record (@$mentions) {

    my $wikiName = $record->{wikiName};
    my $part = $record->{part};
    my $fingerPrint = $record->{fingerPrint};

    next unless Foswiki::Func::checkAccessPermission("VIEW", $wikiName, undef, $topic, $web, $meta);

    if ($this->isNewMention($web, $topic, $record)) {
      $this->writeDebug("$wikiName has been mentioned in $part of $web.$topic: $record->{fragment}");
      push @newMentions, $record;  
      $this->addMention(
        web => $web,
        topic => $topic,
        wikiName => $wikiName,
        mentionedBy => $mentionedBy,
        date => $revInfo->{date},
        part => $part,
        fingerPrint => $fingerPrint
      ) unless $isDry;
    } else {
      #$this->writeDebug("already mentioned $wikiName in $part ... skipping");
    }
  }

  my %isMentioned = map {
      my $key = join("::", $_->{wikiName}, $_->{part}, $_->{fingerPrint}); 
      $key => 1
    } @$mentions;

  #$this->writeDebug("isMentioned=" . dump(\%isMentioned));

  # remove old mentions
  my $it = $this->eachMention(
    web => $web,
    topic => $topic,
  );

  while ($it->hasNext()) {
    my $row = $it->next();

    my $key = join("::", $row->{wikiName}, $row->{part}, $row->{fingerPrint});
    if ($isMentioned{$key}) {
      #$this->writeDebug("... record for $key still found");
      next;
    }

    $this->writeDebug("... removing old mentions for $key in $web.$topic");
    $this->deleteMentions(
      web => $web,
      topic => $topic,
      wikiName => $row->{wikiName},
      part => $row->{part},
      fingerPrint => $row->{fingerPrint},
    ) unless $isDry;
  }

  return \@newMentions;
}

=begin TML

---++ ObjectMethod extractMentions($meta, $mode) -> $mentions

returns a list of mentions found in the given $meta object.
=$mentions= is an array of mentioning records:

  * wikiName: user name being found
  * part: part of the topic within which the mentioning was found, e.g. "Text", formfield, meta data
  * fragment: text fragment containing the mentioning

=cut

sub extractMentions {
  my ($this, $meta, $mode) = @_;

  $mode //= $this->{mode};
  my $mentions = [];

  if ($mode =~ /\b(all|text)\b/) {  
    $this->extractMentionsFromText($meta->text(), "Text", undef, $mentions);
  }

  if ($mode =~ /\b(all|formfields?)\b/) {
    my $formDef = _getFormDef($meta);
    if ($formDef) {
      foreach my $fieldDef (@{$formDef->getFields()}) {

        my $field = $meta->get('FIELD', $fieldDef->{name});
        next unless $field;

        my $val = $field->{value};
        next unless $val;

        if (ref($fieldDef) =~ /^Foswiki::Form::User/) {
          my $wikiNameWeb;
          foreach my $wikiName (split(/\s*,\s*/, $val)) {
            ($wikiNameWeb, $wikiName) = Foswiki::Func::normalizeWebTopicName($Foswiki::cfg{UsersWebName}, $wikiName);
            next if !Foswiki::Func::topicExists($wikiNameWeb, $wikiName) || Foswiki::Func::isGroup($wikiName); # SMELL: there is no Foswiki::Func::isUser()

            #$this->writeDebug("found user in User formfield: $wikiName");
            push @$mentions, $this->createRecord($wikiName, $field->{name});
          }
        } else {
          $this->extractMentionsFromText($val, $field->{name}, undef, $mentions);
        }
      }
    }
  }
  
  foreach my $metaName (sort keys %Foswiki::Meta::VALIDATE) {
    next if $metaName =~ /^(TOPICINFO|TOPICMOVED|FIELD|FORM|FILEATTACHMENT|TOPICPARENT|PREFERENCE)$/; 
  
    if ($metaName eq 'COMMENT') {
      next unless $mode =~ /\b(all|comments?)\b/;
    } else {
      next unless $mode =~ /\b(all|metadata?)\b/;
    }

    foreach my $record ($meta->find($metaName)) {
      foreach my $key (keys %$record) {
        $this->extractMentionsFromText($record->{$key}, ucfirst(lc($metaName)), $record->{name}, $mentions);
      }
    }
  }

  return $mentions;
}

=begin TML

---++ ObjectMethod extractMentionsFromText($text, $part, $id, $mentions) -> $mentions

extracts all mentions from a text. the $part parameter indicates which part of a topic this is
used when creating new records. new records are added to the array ref =$mentions=. If no
=$mentions= parameter is specified a new array is returned.

=cut

sub extractMentionsFromText {
  my ($this, $text, $part, $id, $mentions) = @_;

  $text = _plainify($text);
  return unless $text;

  #$this->writeDebug("called extractMentionsFromText($part)");

  $mentions //= [];
  my $web = $Foswiki::cfg{UsersWebName};

  foreach my $line (split(/\n/, $text)) {
    while ($line =~ /$STARTTOKEN\@($Foswiki::regex{wikiWordRegex})$ENDTOKEN/g) {
      my $wikiName = $1;
      next if !Foswiki::Func::topicExists($web, $wikiName) || Foswiki::Func::isGroup($wikiName);
      push @$mentions, $this->createRecord($wikiName, $part, $id, _extractTextFragment($line, $wikiName));
    }
  }

  return $mentions;
}

=begin TML

---++ ObjectMethod createRecord($wikiName, $part, $id, $fragment) 

creates a mention for the given values. =$part=, =$id= and =$fragment= are optional

=cut

sub createRecord {
  my ($this, $wikiName, $part, $id, $fragment) = @_;

  $fragment //= "";
  $part //= "";
  $id //= "";

  $fragment = Encode::encode_utf8($fragment);
  $this->writeDebug("called createRecord($wikiName, $part, $id, $fragment)");

  return {
    wikiName => $wikiName,
    part => $part,
    fragment => $fragment,
    fingerPrint => Digest::MD5::md5_hex($wikiName, $part, $id, $fragment),
  };
}


=begin TML

---++ ObjectMethod eachMention(%params) -> $iterator

returns a database iterator over all mentions fouund

=cut

sub eachMention {
  my ($this, %params) = @_;

  #$this->writeDebug("called eachMention");

  my @where = ();
  my @values = ();

  foreach my $k (sort keys %params) {
    next if $k eq 'sort' || $k eq 'order';

    my $v = $params{$k};
    next unless defined $v;

    if ($k eq 'from') {
      push @where, "date >= ?";
      push @values, $v;
    } elsif ($k eq 'to') {
      push @where, "date <= ?";
      push @values, $v;
    } else {
      push @where, "$k=?";
      push @values, $v;
    }
  }

  my @order = ();
  my $order = $params{sort} // $params{order};
  if ($order) {
    push @order, "?";
    push @values, $order;
  }

  my $stm = "SELECT * FROM MentionsPlugin_mentions" .
    (@where ? " WHERE ". join(" AND ", @where) : "") . 
    (@order ? " ORDER BY ".join(", ", @order) : "");

  #$this->writeDebug("... stm=$stm");

  return Foswiki::Iterator::DBIterator->new($this->db->handler, $stm, \@values);
}

=begin TML

---++ ObjectMethod isNewMention($web, $topic, $record) -> $boolean

returns true if the given record hasn't been stored in the database yet

=cut

sub isNewMention {
  my ($this, $web, $topic, $record) = @_;

  #$this->writeDebug("called isNewMention($web, $topic, $record->{wikiName}, $record->{part})");
  my $key = join("::", $web, $topic);
  my $oldMentions = $this->getMentionsOfTopic($web, $topic);
  return 1 unless $oldMentions;

  foreach my $mention (@$oldMentions) {
    #$this->writeDebug("mention=".dump($mention));
    next unless 
      $mention->{wikiName} eq $record->{wikiName} && 
      $mention->{part} eq $record->{part};

    my %fingerPrints = map {$_ => 1} split(/,/, $mention->{fingerPrints});

    return 0 if $fingerPrints{$record->{fingerPrint}};
  }

  return 1;
}

=begin TML

---++ ObjectMethod getMentionsOfTopic($web, $topic) -> $array_ref

returns a cached list of all mentions in the given topic

=cut

sub getMentionsOfTopic {
  my ($this, $web, $topic) = @_;

  my $key = join("::", $web, $topic);

  $this->{_mentionsOfTopic}{$key} = $this->getMentions(web => $web, topic => $topic)
    unless $this->{_mentionsOfTopic}{$key};
  
  return $this->{_mentionsOfTopic}{$key};
}

=begin TML

---++ ObjectMethod getMentions(%params) -> $array_ref

returns mentionings in the database 

=cut

sub getMentions {
  my ($this, %params) = @_;

  #$this->writeDebug("called getMentions()");

  my (@where, @values);
  while (my ($k, $v) = each %params) {
    next if $k =~ /^_/;
    push @where, "$k=?";
    push @values, $v;
  }

  my $stm = "SELECT web, topic, part, wikiName, mentionedBy, date, group_concat(fingerPrint) as fingerPrints, count(*) as times from MentionsPlugin_mentions WHERE " .join(" AND ", @where). " GROUP BY web,topic,part,wikiName,part";
  #$this->writeDebug("... stm=$stm");

  return $this->db->handler->selectall_arrayref($stm, {Slice => {}}, @values);
}

=begin TML

---++ ObjectMethod addMention(%params) -> $bool

inserts a mentioning record into the databyse

=cut

sub addMention {
  my ($this, %params) = @_;

  $this->writeDebug("called addMention()");

  $params{mentionedBy} //= Foswiki::Func::getWikiName();
  $params{date} //= time();
  $this->writeDebug("... wikiName=$params{wikiName}, date=".($params{date}//'undef').", by=$params{mentionedBy}. web=$params{web}, topic=$params{topic}");

  my (@fields, @values, @q);
  while (my ($k, $v) = each %params) {
    next if $k =~ /^_/;
    push @fields, $k;
    push @values, $v;
    push @q, '?';
  }

  # clear cache
  #undef $this->{_mentionsOfTopic}{$params{web}, $params{topic}};

  return $this->db->handler->do("INSERT INTO MentionsPlugin_mentions (".join(", ", @fields).") VALUES(".join(", ", @q).")", undef, @values);
}

=begin TML

---++ ObjectMethod moveMentions($fromWeb, $fromTopic, $toWeb, $topTopic ) -> $boolean

moves all mentionings in the database from one place to the other, returns true if the update was successful

=cut

sub moveMentions {
  my ($this, $fromWeb, $fromTopic, $toWeb, $toTopic) = @_;

  $this->writeDebug("called moveMentions");

  return unless $fromWeb && $fromTopic && $toWeb && $toTopic && ($fromWeb ne $toWeb || $fromTopic ne $toTopic);

  $this->writeDebug("from: $fromWeb.$fromTopic to: $toWeb.$toTopic");

  if ($toWeb =~ /$this->{excludeWeb}/ || $toTopic =~ /$this->{excludeTopic}/) {
    return $this->deleteMentions(web => $fromWeb, topic => $fromTopic);
  } 

  return $this->db->handler->do("UPDATE MentionsPlugin_mentions SET web=?, topic=? WHERE web=? AND topic=?",
    undef,
    $toWeb, $toTopic,
    $fromWeb, $fromTopic,
  );
}

=begin TML

---++ ObjectMethod deleteMentions(%params) -> $bool

deletes mentiongs matching the given parameters

=cut

sub deleteMentions {
  my ($this, %params) = @_;

  $this->writeDebug("called deleteMentions()");

  my @where = ();
  my @values = ();
  while (my ($k, $v) = each %params) {
    next unless defined $v;
    push @where, "$k=?";
    push @values, $v;
  }

  my $stm = "DELETE FROM MentionsPlugin_mentions" .  (@where ? " WHERE ". join(" AND ", @where) : "");
  #$this->writeDebug("... stm=$stm");

  return $this->db->handler->do($stm, undef, @values);
}

=begin TML

---++ ObjectMethod writeDebug($msg)

output debug message to STDERR aka server logs

=cut

sub writeDebug {
  my ($this, $msg) = @_;
  #Foswiki::Func::writeDebug("MentionsPlugin::Core - $_[0]");
  print STDERR "MentionsPlugin::Core - $msg\n" if $this->{debug};
}


### static helper

sub _parseTime {
  my $string = shift;

  return unless defined $string;
  return $string if $string =~ /^\d+$/;
  return Foswiki::Time::parseTime($string);
}

sub _formatTime {
  my ($epoch, $format) = @_;

  return "" unless $epoch;

  $format //= $Foswiki::cfg{DateManipPlugin}{DefaultDateTimeFormat} // $Foswiki::cfg{DefaultDateFormat}.' - $hour:$min';

  my $result;
  try {
    $result = Foswiki::Func::formatTime($epoch, $format);
  } catch Error with {};

  $result ||= '';

  return $result;
}

sub _inlineError {
  return "<span class='foswikiAlert'>".shift."</span>";
}

sub _getFormDef {
  my $meta = shift;

  my $formName = $meta->getFormName();
  return unless $formName;

  my ($formWeb, $formTopic) = Foswiki::Func::normalizeWebTopicName($meta->web(), $formName);
  return unless defined $formWeb && defined $formTopic;

  my $session = $Foswiki::Plugins::SESSION;
  my $formDef;
  try {
    $formDef = Foswiki::Form->new($session, $formWeb, $formTopic);
  }
  catch Error with {
    #print STDERR "ERROR: _getFormDef() failed for $formWeb.$formTopic: ".shift."\n";
  };

  return $formDef;
}

sub _extractTextFragment {
  my ($text, $word) = @_;

  my $frag = "";

  if ($text =~ /([^\.\?\!\n]*?\b$word\b[^\.\?\!]*(?:[\.\?\!]|$))/g) {
    $frag = $1;
    $frag =~ s/^\s+//;
    $frag =~ s/\s+$//;
    $frag = "" if $frag =~  /^@?$word$/;
  }

  return $frag;
}

sub _plainify {
  my ($text) = @_;

  $text =~ s/<nop>//g;    # remove foswiki pseudo markup
  $text =~ s/<!--.*?-->//gs;    # remove all HTML comments
  $text =~ s/\&[a-z]+;/ /g;     # remove entities
  $text =~ s/\[\[([^\]]*\]\[)(.*?)\]\]/$2/g;
  $text =~ s/<[^>]*>//g;        # remove all HTML tags
  $text =~ s/[\[\]\*\|=_\&\<\>]/ /g;    # remove Wiki formatting chars
  $text =~ s/^\-\-\-+\+*\s*\!*/ /gm;    # remove heading formatting and hbar
  $text =~ s/^\s+//;                   # remove leading whitespace
  $text =~ s/\s+$//;                   # remove trailing whitespace
  $text =~ s/['"]//;
  $text =~ s/%\w+(?:\{.*?\})?%//g;          # remove macros
  $text =~ s/##.*?#//g;          # remove any explicit numbering stuff
  $text =~ s/#//g;          # remove any explicit numbering stuff

  return $text;
}

sub _sanitizeString {
  my $str = shift;

  return unless defined $str;

  $str =~ s/[^\w\s\.\/\%_\-]//g;

  return $str;
}

1;
