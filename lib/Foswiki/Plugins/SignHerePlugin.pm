# See bottom of file for default license and copyright information
# vim:set et sw=4 ts=4:

=begin TML

---+ package Foswiki::Plugins::SignHerePlugin

=cut

package Foswiki::Plugins::SignHerePlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Foswiki::Time ();

use JSON;

our $VERSION = '0.1';
our $RELEASE = '0.1';
our $SHORTDESCRIPTION = 'Allow specific users to add parameterized signatures to otherwise protected topics';

our $NO_PREFS_IN_TOPIC = 1;

sub initPlugin {
    my ($topic, $web, $user, $installWeb) = @_;

    # check for Plugins.pm versions
    if ($Foswiki::Plugins::VERSION < 2.0) {
        Foswiki::Func::writeWarning('Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm');
        return 0;
    }

    Foswiki::Func::registerTagHandler('SIGNATURES', \&_SIGNATURES);
    Foswiki::Func::registerRESTHandler('submit', \&restSubmit,
        authenticate => 1,
        http_allow => 'POST'
    );

    return 1;
}

# Adapted from Foswiki::Meta (post Release-01x01)
# From a list of pref names, grab the first that is defined
sub _getACL {
    my $meta = shift;
    my ($text, $mode);
    while (!defined($text) && @_) {
        $mode = shift;
        $text = $meta->getPreference($mode);
    }
    return undef if !defined($text);

    # Remove HTML tags (compatibility, inherited from Users.pm
    $text =~ s/(<[^>]*>)//g;

    # Dump the users web specifier if userweb
    my @list = grep { /\S/ } map {
        s/^($Foswiki::cfg{UsersWebName}|%USERSWEB%|%MAINWEB%)\.//;
        $_
    } split( /[,\s]+/, $text );
    return \@list;
}

# Fetches pref from topic and falls back to web, and finally a default value
# specified by the caller
# Checks two prefs in order: $name_$location (if defined) and $name
sub _getPref {
    my ($meta, $name, $location, $default) = @_;
    my $res;
    if (defined($location)) {
        $location = uc($location);
        $res = $meta->getPreference("${name}_$location");
        return $res if defined $res;
    }
    $res = $meta->getPreference($name);
    return $res if defined $res;

    if (defined($location)) {
        $res = $meta->getContainer()->getPreference("${name}_$location");
        return $res if defined $res;
    }
    $res = $meta->getContainer()->getPreference($name);
    return $res if defined $res;

    return $default;
}
sub _getPref_bool {
    my $res = _getPref(@_);
    return ($res =~ /^(?:1|on|yes|true)$/i);
}

sub _valid_states {
    # @_: ($meta, $location)
    # Get list of states
    my $states = _getPref($_[0], 'SIGNATURESTATES', $_[1], 'OK=ok,Not OK=notok,Abstain=abstain');
    my @states = map { /(.*)=(.*)/ && [$1 => $2] or /(.*)/ && [$1 => $1] } split(/\s*,\s*/, $states);
    my @state_labels = map { $_->[0] } @states;
    @states = map { $_->[1] } @states;
    my %states;
    @states{@states} = @state_labels;
    (\@states, \@state_labels, \%states);
}

sub _current_signatures {
    my ($meta, $location) = @_;
    my $signature = $meta->get('SIGNATURE', $location);
    return undef unless defined $signature;
    $signature = $signature->{data};
    return undef unless defined $signature && $signature !~ /^\s*$/;

    $signature = eval { from_json($signature); };
    if ($@) {
        Foswiki::Func::writeWarning("Error decoding signatures for ".$meta->web.".".$meta->topic.": ".$@);
        return undef;
    }
    return $signature;
}

sub _update_signatures {
    my ($meta, $location, $signatures) = @_;
    $meta->putKeyed('SIGNATURE', { name => $location, data => to_json($signatures) });
    $meta->saveAs($meta->web, $meta->topic, dontlog => 1, minor => 1);
}

sub _states_option_elems {
    my ($states, $state_map, $selected) = @_;
    my $res = '';
    foreach my $s (@$states) {
        $res .= "<option value=\"$s\"";
        $res .= ' selected="selected" style="font-weight:bold;"' if defined($selected) && $s eq $selected;
        my $label = $state_map->{$s};
        $label = $s unless defined $label;
        $res .= ">$label</option>";
    }
    return $res;
}

sub _state_button {
    my ($states, $state_map, $selected, $web, $topic, $location) = @_;
    my $button = '<form class="signherebutton"><select name="state"><option></option>';
    $button .= _states_option_elems($states, $state_map, $selected);
    $button .= '</select>';
    $button .= "<input type=\"hidden\" name=\"target\" value=\"$web.$topic\">";
    $button .= "<input type=\"hidden\" name=\"location\" value=\"$location\">";
    my $label = ($selected eq '') ? "Sign" : "Amend";
    $button .= ' %BUTTON{"%MAKETEXT{"'.$label.'"}%" type="submit" class="foswikiRight"}% %CLEAR%</form>';
    return $button;
}

sub _SIGNATURES {
    my($session, $params, $topic, $web, $topicObject) = @_;

    my $id = $params->{_DEFAULT} || 'main';
    my $theweb = $params->{web} || $web;
    my $thetopic = $params->{topic} || $topic;
    my $location = $params->{location} || 'main';

    ($theweb, $thetopic) = Foswiki::Func::normalizeWebTopicName($theweb, $thetopic);
    my ($meta) = Foswiki::Func::readTopic($web, $topic);
    unless ($meta->haveAccess) {
        return '%RED%SIGNATURES: %MAKETEXT{"access denied on topic"}%%ENDCOLOR%';
    }

    my $lang = $session->i18n->language;
    $lang = 'en' unless -f "$Foswiki::cfg{PubDir}/$Foswiki::cfg{SystemWebName}/SignHerePlugin/signhere_$lang.js";
    Foswiki::Func::addToZone('script', 'SIGNHEREPLUGIN::JS', <<EOC, 'JQUERYPLUGIN');
<script type="text/javascript" src="$Foswiki::cfg{PubUrlPath}/$Foswiki::cfg{SystemWebName}/SignHerePlugin/signhere.js"></script>
<script type="text/javascript" src="$Foswiki::cfg{PubUrlPath}/$Foswiki::cfg{SystemWebName}/SignHerePlugin/signhere_$lang.js"></script>
EOC

    my $only = $params->{only};
    my @only = map { $session->{users}->getCanonicalUserID($_) } split(/\s*,\s*/, $only);
    my $allowed = _getACL($meta, 'ALLOWSIGNHERE_'.uc($location), 'ALLOWSIGNHERE');
    return '' unless defined $allowed;
    $allowed = [ map { $session->{users}->getCanonicalUserID($_) } @$allowed ];
    $allowed = [ grep { grep($_, @only) } @$allowed ] if defined $only;

    my ($states, $state_labels, $state_map) = _valid_states($meta, $location);
    return '' unless defined $states;

    my $signatures = _current_signatures($meta, $location);

    my $res = '';
    $res .= $params->{header} if defined $params->{header};
    my $format = $params->{format};
    $format = "| \$wikiname | \$status_or_button |" unless defined $format;
    my $separator = $params->{separator};
    $separator = "\$n" unless defined $separator;
    $separator =~ s/\$n/\n/g;
    my $first = 1;
    foreach my $a (@$allowed) {
        next if !defined($a) || $a =~ /^\s*$/;
        $first ? ($first = 0) : ($res .= $separator);
        my $out = $format;
        $out =~ s/\$wikiname/$session->{users}->getWikiName($a)/eg;
        $out =~ s/\$(?:login|user)(?:name)?/$session->{users}->getLoginName($a)/eg;

        my $state = '';
        my $state_label = '';
        my $timestamp = '';
        if (defined $signatures && exists $signatures->{$a}) {
            $state = $signatures->{$a};
            $timestamp = $state->{at};
        }
        my $button = '';
        if (ref $state) {
            $state = $state_label = $state->{state};
            $state_label = $state_map->{$state} if exists $state_map->{$state};
            $state_label .= ' ('. Foswiki::Time::formatTime($timestamp) .')';
        }
        my $lock = _getPref_bool($meta, 'SIGNHERELOCKED', $location, 0);
        # SMELL: doesn't support groups in ACL yet
        if (!$lock && $a eq $session->{user}) {
            $button = _state_button($states, $state_map, $state, $theweb, $thetopic, $location);
        }

        $out =~ s/\$timestamp/$timestamp ne '' ? Foswiki::Time::formatTime($timestamp) : ''/eg;
        $out =~ s/\$status_or_button/$button || $state_label/eg;
        $out =~ s/\$button/$button/g;
        $out =~ s/\$status_code/$state/g;
        $out =~ s/\$status/$state_label/g;
        $res .= $out;
    }
    return $res;
}


sub restSubmit {
    my ($session, $subject, $verb, $response) = @_;
    my $query = $session->{request};
    my ($web, $topic) = Foswiki::Func::normalizeWebTopicName('', $query->param('target'));
    my $location = $query->param('location') || 'main';
    return '{"status":"error","code":"invalid-location"}' unless $location =~ /^[a-z0-9_]+$/;
    return '{"status":"error","code":"needs-target"}' unless $web && $topic;
    my ($meta) = Foswiki::Func::readTopic($web, $topic);
    return '{"status":"error","code":"invalid-target"}' unless defined $meta;

    #my $withdraw = $query->param('withdraw');
    my $state = $query->param('state');
    return '{"status":"error","code":"needs-state"}' unless defined($state);# || $withdraw;

    # Check permissions
    my $allowed = _getACL($meta, 'ALLOWSIGNHERE_'.uc($location), 'ALLOWSIGNHERE');
    $allowed = [] unless defined $allowed;
    # If nothing was set explicitly, we deny
    my $forbidden = '{"status":"error","code":"forbidden"}';
    my $u = $session->{user};
    return $forbidden if !$session->{users}->isInUserList($u, $allowed);

    # Looks good... but also check lock
    my $lock = _getPref_bool($meta, 'SIGNHERELOCKED', $location);
    return '{"status":"error","code":"locked"}' if $lock;

    my ($states) = _valid_states($meta);
    #$withdraw or
    grep($state, @$states) or return '{"status":"error","code":"invalid-state"}';

    my ($signatures) = _current_signatures($meta, $location);
    #if ($withdraw) {
    #    delete $signatures->{$u};
    #else {
        $signatures->{$u} = { state => $state, at => time };
    #}
    _update_signatures($meta, $location, $signatures);

    return to_json({
        status => 'ok',
        label => $session->i18n->maketext("Amend"),
    });
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Author: %$AUTHOR%

Copyright (C) 2013 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
