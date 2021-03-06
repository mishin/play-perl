use t::common;
use parent qw(Test::Class);

use Email::Sender::Simple;

sub setup :Tests(setup) {
    Dancer::session->destroy;
    reset_db();
}

sub add_comment :Tests {

    http_json GET => "/api/fakeuser/blah";

    my $quest_result = http_json POST => '/api/quest', { params => { user => 'blah', name => 'foo', status => 'open' } };
    my $quest_id = $quest_result->{_id};

    my $first = http_json POST => "/api/quest/$quest_id/comment", { params => { body => 'first comment!' } };
    my $second = http_json POST => "/api/quest/$quest_id/comment", { params => { body => 'second comment!' } };

    cmp_deeply
        $first,
        { _id => re('^\S+$'), body_html => re('first') },
        'add comment result';

    my $list = http_json GET => "/api/quest/$quest_id/comment";
    cmp_deeply
        $list,
        [
            { _id => $first->{_id}, ts => re('^\d+$'), body => 'first comment!', author => 'blah', quest_id => $quest_id, body_html => re('first') },
            { _id => $second->{_id}, ts => re('^\d+$'), body => 'second comment!', author => 'blah', quest_id => $quest_id, body_html => re('second') },
        ]
}

sub remove :Tests {

    http_json GET => "/api/fakeuser/blah";

    my $quest_result = http_json POST => '/api/quest', { params => { name => 'foo', status => 'open' } };
    my $quest_id = $quest_result->{_id};

    my $comment = http_json POST => "/api/quest/$quest_id/comment", { params => { body => "I'm just a little comment!" } };
    my $second_comment = http_json POST => "/api/quest/$quest_id/comment", { params => { body => "another one" } };

    http_json GET => "/api/fakeuser/other-user";

    my $response = dancer_response DELETE => "/api/quest/$quest_id/comment/$comment->{_id}";
    is $response->status, 500, "can't delete another user's comment";
    like decode_json($response->content)->{error}, qr/access denied/;

    my $comments = http_json GET => "/api/quest/$quest_id/comment";
    is scalar @$comments, 2;
    like $comments->[0]->{body}, qr/little comment/, 'comment still exists';

    Dancer::session login => 'blah';
    http_json DELETE => "/api/quest/$quest_id/comment/$comment->{_id}";

    $comments = http_json GET => "/api/quest/$quest_id/comment";
    is scalar @$comments, 1, 'comment really removed';
    like $comments->[0]->{body}, qr/another/, 'another comment still exists';
}

sub body_html :Tests {
    http_json GET => "/api/fakeuser/blah";

    my $quest_result = http_json POST => '/api/quest', { params => { user => 'blah', name => 'foo', status => 'open' } };
    my $quest_id = $quest_result->{_id};

    my $body = 'To **boldly** go where no man has gone before';

    my $add_result = http_json POST => "/api/quest/$quest_id/comment", { params => { body => $body } };
    like $add_result->{body_html}, qr{To <strong>boldly</strong> go};

    my $comments = http_json GET => "/api/quest/$quest_id/comment";
    like $comments->[0]{body_html}, qr{To <strong>boldly</strong> go};
    is $comments->[0]{body}, $body;
}

sub comment_events :Tests {
    http_json GET => "/api/fakeuser/blah";

    my $quest_result = http_json POST => '/api/quest', { params => { user => 'blah', name => 'foo', status => 'open' } };
    my $quest_id = $quest_result->{_id};

    my $add_result = http_json POST => "/api/quest/$quest_id/comment", { params => { body => 'cbody, **bold cbody**' } };

    my $events = http_json GET => "/api/event";
    cmp_deeply $events->[0], {
        _id => re('^\S+$'),
        action => 'add',
        object_type => 'comment',
        author => 'blah',
        object_id => $add_result->{_id},
        ts => re('^\d+$'),
        object => {
            author => 'blah',
            body => 'cbody, **bold cbody**',
            body_html => re('<strong>bold cbody</strong>'),
            quest => {
                _id => $quest_id,
                ts => re('^\d+'),
                name => 'foo',
                status => 'open',
                user => 'blah',
                team => ['blah'],
                author => 'blah',
            },
            quest_id => $quest_id,
        },
    }, 'comment-add event';
}

sub perl_get_one :Tests {

    http_json GET => "/api/fakeuser/blah";

    my $quest_result = http_json POST => '/api/quest', { params => { user => 'blah', name => 'fff', status => 'open' } };
    my $quest_id = $quest_result->{_id};
    my $comment_result = http_json POST => "/api/quest/$quest_id/comment", { params => { body => "Blah" } };
    my $comment_id = $comment_result->{_id};

    my $comment = http_json GET => "/api/quest/$quest_id/comment/$comment_id";
    like $comment->{body}, qr/Blah/;
}

sub edit_comment :Tests {

    http_json GET => "/api/fakeuser/blah";

    my $quest_result = http_json POST => '/api/quest', { params => { user => 'blah', name => 'foo', status => 'open' } };
    my $quest_id = $quest_result->{_id};

    my $comment_result = http_json POST => "/api/quest/$quest_id/comment", { params => { body => "Commentin" } };
    my $comment_id = $comment_result->{_id};
    like $comment_id, qr/^\S+$/, 'comment id looks good';

    my $update_result = http_json PUT => "/api/quest/$quest_id/comment/$comment_id", { params => { body => "Commenting (fixed a typo)" } };
    my $comments = http_json GET => "/api/quest/$quest_id/comment";
    like $comments->[0]{body}, qr/fixed a typo/, 'comment body got updated';
}

sub email_comment :Tests {
    # 'foo' posts a quest, 'bar' comments on it

    http_json GET => "/api/fakeuser/foo";

    register_email 'foo' => { email => 'test@example.com', notify_comments => 1, notify_likes => 0 };

    my $quest_result = http_json POST => '/api/quest', { params => { user => 'blah', name => 'foo-quest', status => 'open' } };
    my $quest_id = $quest_result->{_id};

    http_json POST => "/api/quest/$quest_id/comment", { params => { body => "self-commenting." } };
    is(Email::Sender::Simple->default_transport->delivery_count, 0, "self-comment does't send an email");

    http_json GET => "/api/fakeuser/bar";
    http_json POST => "/api/quest/$quest_id/comment", { params => { body => "Hello sweetie." } };

    my @deliveries = Email::Sender::Simple->default_transport->deliveries;
    is scalar(@deliveries), 1, '1 email sent';
    cmp_deeply $deliveries[0]{envelope}, {
        from => 'notification@localhost',
        to => [ 'test@example.com' ],
    }, 'from & to addresses';
}

sub likes :Tests {
    http_json GET => "/api/fakeuser/pink";

    my $quest_result = http_json POST => '/api/quest', { params => { user => 'blah', name => "I've got a little black book", status => 'open' } };
    my $quest_id = $quest_result->{_id};

    http_json GET => "/api/fakeuser/floyd";

    my $first_comment = http_json POST => "/api/quest/$quest_id/comment", { params => { body => 'Hello?' } };
    my $second_comment = http_json POST => "/api/quest/$quest_id/comment", { params => { body => 'Is there anybody out there?' } };
    my $comment_id = $second_comment->{_id};

    my $response = dancer_response POST => "/api/quest/$quest_id/comment/$comment_id/like";
    is $response->status, 500, 'self-likes are forbidden';
    like $response->content, qr/unable to like your own comment/, "comment author can't like it";

    Dancer::session login => 'pink';
    $response = dancer_response POST => "/api/quest/$quest_id/comment/$comment_id/like";
    is $response->status, 200, 'quest author is allowed to like comments on his quest';

    http_json GET => "/api/fakeuser/worm";

    $response = dancer_response POST => "/api/quest/$quest_id/comment/$comment_id/like";
    is $response->status, 200, 'other (imaginary) people are allowed to like comments too';

    my $comments = http_json GET => "/api/quest/$quest_id/comment";
    ok not(defined $comments->[0]->{likes}), 'no likes on the first comment';
    cmp_deeply $comments, [
        ignore,
        superhashof({
            likes => ['pink', 'worm'],
        }),
    ], 'really, liked';

    Dancer::session login => 'worm';
    $response = dancer_response POST => "/api/quest/$quest_id/comment/$comment_id/unlike";
    is $response->status, 200, 'comment can be unliked';

    $comments = http_json GET => "/api/quest/$quest_id/comment";
    cmp_deeply $comments, [
        ignore,
        superhashof({
            likes => ['pink'],
        }),
    ], 'really, unliked';
}

__PACKAGE__->new->runtests;
