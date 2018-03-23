/* citus--7.3-3--7.3-4 */

CREATE FUNCTION citus.mitmproxy(text)
RETURNS text AS $$
  use strict;
  use warnings;

  my $command = $_[0];
  my $filename = '/home/brian/Work/citus/src/test/regress/mitmproxy.fifo';

  my $fh;

  open($fh, '>', $filename) or die 'could not write to mitmproxy';
  print($fh "command\n");
  close($fh);

  open($fh, '<', $filename) or die 'could not read from mitmproxy';
  my $result = <$fh>;
  close($fh);

  return $result;
$$ LANGUAGE plperlu;
