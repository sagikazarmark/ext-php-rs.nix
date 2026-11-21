--TEST--
grpc: an insecure channel and its target (a channel connects lazily: no server needed)
--EXTENSIONS--
grpc
--FILE--
<?php
$channel = new Grpc\Channel('localhost:50051', ['credentials' => Grpc\ChannelCredentials::createInsecure()]);
echo $channel->getTarget(), ' ', Grpc\STATUS_OK, "\n";
$channel->close();
?>
--EXPECT--
localhost:50051 0
