package Play::Route::Users;

use Dancer ':syntax';

use LWP::UserAgent;
use JSON qw(decode_json);

use Dancer::Plugin::Auth::Twitter;
auth_twitter_init();

use JSON;
use Play::DB qw(db);

get '/auth/twitter' => sub {
    if (not session('twitter_user')) {
        redirect auth_twitter_authenticate_url;
    } else {

        my $twitter_login = session('twitter_user')->{screen_name} or die "no twitter login in twitter_user session field";
        my $user = db->users->get_by_twitter_login($twitter_login);
        if ($user) {
            session 'login' => $user->{login};
        }
        redirect "/register";
    }
};

post '/auth/persona' => sub {
    session 'persona_email' => undef;

    my $assertion = param('assertion') or die "no assertion specified";
    my $ua = LWP::UserAgent->new;
    my $response = $ua->post('https://verifier.login.persona.org/verify', {
        assertion => $assertion,
        audience => setting('hostport'),
    });
    die "Invalid response from persona.org: ".$response->status_line unless $response->is_success;

    my $json = $response->decoded_content;
    my $verification_data = decode_json($json);

    my $status = $verification_data->{status};
    die "verification_data status is not okay (it's $status); json: $json" unless $status eq 'okay';

    my $email = $verification_data->{email};
    unless ($email) {
        die "No email in verification_data";
    }
    session 'persona_email' => $email;

    my $login = db->users->get_by_email($email);
    if ($login) {
        session 'login' => $login;
    }

    return { result => 'ok' };
};

prefix '/api';

get '/current_user' => sub {

    my $user = {};
    my $login = session('login');
    if ($login) {
        $user = db->users->get_by_login($login);
        unless ($user) {
            die "user '$login' not found";
        }
        $user->{registered} = 1;

        $user->{settings} = db->users->get_settings($login);
        $user->{notifications} = db->notifications->list($login);
    }
    else {
        $user->{registered} = 0;
    }

    if (session('twitter_user')) {
        $user->{twitter} = session('twitter_user');
    }

    if (session('persona_email') and not $user->{registered}) {
        $user->{settings}{email} = session('persona_email');
        $user->{settings}{email_confirmed} = 'persona';
    }

    return $user;
};

# user settings are private; you can't get settings of other users
get '/current_user/settings' => sub {
    my $login = session('login');
    die "not logged in" unless session->{login};
    return db->users->get_settings($login);
};

any ['put', 'post'] => '/current_user/settings' => sub {
    die "not logged in" unless session->{login};
    db->users->set_settings(
        session->{login} => _expand_settings(scalar params()),
        (session('persona_email') ? 1 : 0) # force 'email_confirmed' setting
    );
    return { result => 'ok' };
};

post '/current_user/dismiss_notification/:id' => sub {
    my $login = session('login');
    die "not logged in" unless session->{login};
    db->notifications->remove(param('id'), $login);
    return { result => 'ok' };
};

get '/user/:login' => sub {
    my $login = param('login');
    my $user = db->users->get_by_login($login);
    unless ($user) {
        die "user '$login' not found";
    }

    return $user;
};

sub _expand_settings {
    my ($settings) = @_;

    my $more_settings = {};
    if (session('persona_email')) {
        $more_settings->{email} = session('persona_email');
    }
    return { %$settings, %$more_settings };
}

post '/register' => sub {
    my $login = param('login') or die 'no login specified';

    unless ($login =~ /^\w+$/) {
        status 'bad request';
        return "Invalid login '$login', only alphanumericals are allowed";
    }

    if (db->users->get_by_login($login)) {
        die "User $login already exists";
    }

    my $user = { login => $login };
    my $more_settings = {};

    my $settings = param('settings') || '{}';
    $settings = decode_json($settings);

    if (session('twitter_user')) {
        my $twitter_login = session('twitter_user')->{screen_name};

        if (db->users->get_by_twitter_login($twitter_login)) {
            die "Twitter login $twitter_login is already bound";
        }

        $user->{twitter} = { screen_name => $twitter_login };
    }
    elsif (session('persona_email')) {
        $more_settings->{email} = session('persona_email');
    }
    else {
        die "not authorized by any 3rd party (either twitter or persona)";
    }

    # note that race condition is still possible after these checks
    # that's ok, mongodb will throw an exception

    db->users->add($user);

    db->users->set_settings(
        $login => _expand_settings($settings),
        # TODO - copypasted from /register, refactor!
        (session('persona_email') ? 1 : 0) # force 'email_confirmed' setting
    );

    session 'login' => $login;

    return { status => "ok", user => $user };
};

post '/register/resend_email_confirmation' => sub {
    my $login = session('login');
    die "not logged in" unless session->{login};
    db->users->resend_email_confirmation($login);
    return { result => 'ok' };
};

# user doesn't need to be logged to use this route
post '/register/confirm_email' => sub {
    # throws an exception if something's wrong
    db->users->confirm_email(param('login') => param('secret'));
    return { confirmed => 1 };
};

get '/user' => sub {
    return db->users->list({
        map { param($_) ? ($_ => param($_)) : () } qw/ sort order limit offset /,
    });
};

get '/user_count' => sub {
    my $count = scalar @{ db->users->list };
    return { count => $count };
};

post '/logout' => sub {

    session->destroy(session); #FIXME: workaround a buggy Dancer::Session::MongoDB

    return {
        status => 'ok'
    };
};

if ($ENV{DEV_MODE}) {
    get '/fakeuser/:login' => sub {
        my $login = param('login');
        session 'login' => $login;

        my $user = { login => $login };

        unless (param('notwitter')) {
            session 'twitter_user' => { screen_name => $login } unless param('notwitter');
            $user->{twitter} = { screen_name => $login };
        }

        db->users->get_by_login($login) or db->users->add($user);
        return { status => 'ok', user => $user };
    };
}

true;
