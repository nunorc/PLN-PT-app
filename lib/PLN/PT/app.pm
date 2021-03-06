package PLN::PT::app;
use Dancer2;
use Dancer2::Plugin::Locale::Wolowitz;

use File::Temp qw/tempdir/;;
use Path::Tiny;
use Cwd;
use JSON::XS;
use LWP::UserAgent;
use utf8::all;
use Encode;
use Tree::Simple;
use Tree::Simple::View::ASCII;
use Text::Markdown;
use HTTP::Request;
use LWP::UserAgent;
use utf8::all;

our $VERSION = '0.1';

# recompile templates based on data files
for my $t (qw/resources/) {
  print STDERR "Building: ${t}_data.tt ..";
  _md2tt($t);
  print STDERR "done!\n";
}

hook 'before' => sub {
  my $l = session 'lang';
  unless ($l) {
    session 'lang' => 'pt';
  }
};

get '/lang/:l' => sub {
  my $l = param 'l';
  if ($l) { session 'lang' => $l; }
  redirect request->referer;
};

get '/' => sub {
  template 'index' => { index=>1 };
};

get '/resources' => sub {
  template 'resources';
};

get '/api' => sub {
  template 'api' => { api => 1 };
};

get '/online' => sub {
  template 'online' => { online => 1 };
};

post '/online' => sub {
  my $text = param 'text';
  redirect '/online' unless $text;

  my $process = param 'process';

  my $opts = { };

  my ($data, $json, $raw);
  if ($process) {
    my $url = "http://api.pln.pt/$process";

    $json = _do_post($url, $text, $opts);
    $data = JSON::XS->new->decode($json);
    $raw = _json2raw($process, $data);
  }

  my ($parse_tree, $ascii_tree);
  if (lc($process) eq 'dep_parser') {
    $ascii_tree = _build_ascii_tree($data);
  }

  template 'online' => {
      online => 1,
      text   => $text,
      json   => $json,
      raw    => $raw,
      myproc => $process,
      parse_tree => $parse_tree,
      ascii_tree => $ascii_tree,
    };
};

sub _do_post {
  my ($url, $text, $opts) = @_;

  # handle options
  my @opts;
  foreach (keys %$opts) {
    push @opts, "$_=$opts->{$_}";
  }
  $url = $url . "?" . join('&', @opts);

  my $req = HTTP::Request->new(POST => $url);
  my $ua = LWP::UserAgent->new;
  $req->content(Encode::encode_utf8($text));

  my $json;
  my $res = $ua->request($req);
  if ($res->is_success) {
    $json = $res->decoded_content;
    $json = $res->content unless $json;
  }
  else {
    print STDERR "HTTP POST error: ", $res->code, " - ", $res->message, "\n";
    return undef;
  }

  if ($url =~ m/dep_parser.*?$/) {
    return $json;
  }
  else {
    return Encode::decode_utf8($json);
  }
}

sub _json2raw {
  my ($process, $json) = @_;

  my @l;
  if ($process eq 'tokenizer') {
    @l = @$json;
  }
  if ($process eq 'tagger') {
    for (@$json) {
      push @l, join("\t", $_->{form}, $_->{lemma}, $_->{pos}, $_->{prob});
    }
  }

  return join("\n", @l);
}

sub _build_ascii_tree {
  my ($data) = @_;
  my $tree;

  for (@$data) {
    if ($_->{deprel} eq 'ROOT') {
      $tree = Tree::Simple->new(_tree_build_str($_), Tree::Simple->ROOT);
      _tree_add_child($_, $tree, $data);
    }
  }

  my $tree_view = Tree::Simple::View::ASCII->new($tree);
  $tree_view->includeTrunk(1);
  return $tree_view->expandAll();
}

sub _tree_build_str {
  my ($token) = @_;
  my $str = join(' ', $token->{form}, $token->{upostag}, $token->{deprel});
  return $str;
}

sub _tree_add_child {
  my ($token, $tree, $data) = @_;

  for (@$data) {
    if ($_->{head} eq $token->{id}) {
      my $t = Tree::Simple->new(_tree_build_str($_), $tree);
      _tree_add_child($_, $t, $data);
    }
  }

  return $tree;
}

sub _md2tt {
  my ($t) = @_;

  my $md = path("data/$t.md")->slurp;
  my $html = Text::Markdown::markdown($md);
  $html =~ s/<ul>/<ul class="collection">/g;
  $html =~ s/<li>/<li class="collection-item">/g;
  path("views/${t}_data.tt")->spew($html);
}

true;

