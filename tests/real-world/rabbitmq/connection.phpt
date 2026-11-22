--TEST--
rabbitmq_ext: its exceptions, and a connection refused with a ConnectionException (no server needed)
--EXTENSIONS--
rabbitmq_ext
--FILE--
<?php
foreach (['Connection', 'Publish', 'Consume', 'Message'] as $kind) {
    echo $kind, 'Exception: ', is_subclass_of("RabbitMQ\\{$kind}Exception", RabbitMQ\Exception::class) ? 'yes' : 'no', "\n";
}

try {
    new RabbitMQ\Connection('amqp://guest:guest@127.0.0.1:1/%2f');
    echo "connected\n";
} catch (RabbitMQ\ConnectionException $e) {
    echo get_class($e), "\n";
}
?>
--EXPECT--
ConnectionException: yes
PublishException: yes
ConsumeException: yes
MessageException: yes
RabbitMQ\ConnectionException
