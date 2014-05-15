#!perl -T

use Test::More tests => 10;
use Lingua::Tok;
use Data::Dumper;
use utf8;

# Basic word split.
my $t = Lingua::Tok->new();

@tokens = $t->text('This is a simple sentence without punctuation');
is_deeply \@tokens, ['This', 'is', 'a', 'simple', 'sentence', 'without', 'punctuation'];

# Basic split with all spaces and whitespace.
@tokens = $t->tokens('This is a  sentence with a double space');
is_deeply \@tokens, ['This', ['S', ' '], 'is', ['S', ' '], 'a', ['S', '  '],
                     'sentence', ['S', ' '], 'with', ['S', ' '], 'a', ['S', ' '],
                     'double', ['S', ' '], 'space'];
                     
# Basic split with some formatting.
@tokens = $t->tokens('This is a <i>formatted</i> sentence<df fontcolor="red">, right?');
#diag Dumper (\@tokens);
is_deeply \@tokens, ['This', ['S', ' '], 'is', ['S', ' '], 'a', ['S', ' '], ['F', '<i>'], 'formatted', ['F', '</i>'],
                     ['S', ' '], 'sentence', ['F', '<df fontcolor="red">'], ['P', ','], ['S', ' '], 'right', ['P', '?']];

# And some entities.
@tokens = $t->tokens('Es gibt auch die M&ouml;glichkeit, <i>Entit&auml;ten</i> zu benutzen.');
is_deeply \@tokens, ['Es', ['S', ' '], 'gibt', ['S', ' '], 'auch', ['S', ' '], 'die', ['S', ' '], 'Möglichkeit', ['P', ','], ['S', ' '],
                     ['F', '<i>'], "Entitäten", ['F', '</i>'], ['S', ' '], 'zu', ['S', ' '], 'benutzen', ['P', '.']];

# 2011-11-22 test case (apparently a blank token at the end of the buffer, leading to a loop):
@tokens = $t->text('according to the IEC 61639, chapter 4 :');
is_deeply \@tokens, ['according', 'to', 'the', 'IEC', '61639', ['P', ','], 'chapter', '4', ['P', ':']];

# Word-initial and -final punctuation.
@tokens = $t->text('A \'sentence\' with punctuation.');
is_deeply \@tokens, ['A', ['P', "'"], 'sentence', ['P', "'"], 'with', 'punctuation', ['P', '.']];

# Words only, without spaces or punctuation.
@tokens = $t->words('A \'sentence\' with punctuation.');
is_deeply \@tokens, ['A', 'sentence', 'with', 'punctuation'];

@tokens = $t->text("We aren't fooled by a complicated URL: http://www.myserver.com/page/page.html?GT+0+fourteen%20long+thing.");
#diag Dumper (\@tokens);  # -- yes, we still are.

# Phrases, given stopwords.
$t->stopwords ('a', 'of', 'by');  # Obviously just a test.
@phrases = $t->phrases ('A series of phrases delineated by stop words.');
#diag Dumper (\@phrases);
is_deeply \@phrases, [['series'],
                      ['phrases', 'delineated'],
                      ['stop', 'words']];

# n-grams permutated from those phrases.                      
@phrases = $t->ngrams ('A series of phrases delineated by many more stop words.');
#diag Dumper (\@phrases);
is_deeply \@phrases, ['series', 'phrases', 'delineated', 'phrases delineated', 'many', 'more', 'stop', 'words', 'many more', 'more stop', 'stop words',
                      'many more stop', 'more stop words', 'many more stop words'];
                      
$t->min_ngram(2);
@phrases = $t->ngrams ('A series of phrases delineated by many more stop words.');
#diag Dumper (\@phrases);
is_deeply \@phrases, ['phrases delineated', 'many more', 'more stop', 'stop words',
                      'many more stop', 'more stop words', 'many more stop words'];