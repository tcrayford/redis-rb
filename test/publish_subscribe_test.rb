# encoding: UTF-8

require File.expand_path("helper", File.dirname(__FILE__))

class TestPublishSubscribe < Test::Unit::TestCase

  include Helper::Client

  class TestError < StandardError
  end

  def test_subscribe_and_unsubscribe
    @subscribed = false
    @unsubscribed = false

    wire = Wire.new do
      r.subscribe("foo") do |on|
        on.subscribe do |channel, total|
          @subscribed = true
          @t1 = total
        end

        on.message do |channel, message|
          if message == "s1"
            r.unsubscribe
            @message = message
          end
        end

        on.unsubscribe do |channel, total|
          @unsubscribed = true
          @t2 = total
        end
      end
    end

    # Wait until the subscription is active before publishing
    Wire.pass while !@subscribed

    Redis.new(OPTIONS).publish("foo", "s1")

    wire.join

    assert @subscribed
    assert_equal 1, @t1
    assert @unsubscribed
    assert_equal 0, @t2
    assert_equal "s1", @message
  end

  def test_psubscribe_and_punsubscribe
    @subscribed = false
    @unsubscribed = false

    wire = Wire.new do
      r.psubscribe("f*") do |on|
        on.psubscribe do |pattern, total|
          @subscribed = true
          @t1 = total
        end

        on.pmessage do |pattern, channel, message|
          if message == "s1"
            r.punsubscribe
            @message = message
          end
        end

        on.punsubscribe do |pattern, total|
          @unsubscribed = true
          @t2 = total
        end
      end
    end

    # Wait until the subscription is active before publishing
    Wire.pass while !@subscribed

    Redis.new(OPTIONS).publish("foo", "s1")

    wire.join

    assert @subscribed
    assert_equal 1, @t1
    assert @unsubscribed
    assert_equal 0, @t2
    assert_equal "s1", @message
  end

  def test_subscribe_connection_usable_after_raise
    @subscribed = false

    wire = Wire.new do
      begin
        r.subscribe("foo") do |on|
          on.subscribe do |channel, total|
            @subscribed = true
          end

          on.message do |channel, message|
            raise TestError
          end
        end
      rescue TestError
      end
    end

    # Wait until the subscription is active before publishing
    Wire.pass while !@subscribed

    Redis.new(OPTIONS).publish("foo", "s1")

    wire.join

    assert_equal "PONG", r.ping
  end

  def test_psubscribe_connection_usable_after_raise
    @subscribed = false

    wire = Wire.new do
      begin
        r.psubscribe("f*") do |on|
          on.psubscribe do |pattern, total|
            @subscribed = true
          end

          on.pmessage do |pattern, channel, message|
            raise TestError
          end
        end
      rescue TestError
      end
    end

    # Wait until the subscription is active before publishing
    Wire.pass while !@subscribed

    Redis.new(OPTIONS).publish("foo", "s1")

    wire.join

    assert_equal "PONG", r.ping
  end

  def test_subscribe_within_subscribe
    @channels = []

    wire = Wire.new do
      r.subscribe("foo") do |on|
        on.subscribe do |channel, total|
          @channels << channel

          r.subscribe("bar") if channel == "foo"
          r.unsubscribe if channel == "bar"
        end
      end
    end

    wire.join

    assert_equal ["foo", "bar"], @channels
  end

  def test_other_commands_within_a_subscribe
    assert_raise Redis::CommandError do
      r.subscribe("foo") do |on|
        on.subscribe do |channel, total|
          r.set("bar", "s2")
        end
      end
    end
  end

  def test_subscribe_without_a_block
    assert_raise LocalJumpError do
      r.subscribe("foo")
    end
  end

  def test_unsubscribe_without_a_subscribe
    assert_raise RuntimeError do
      r.unsubscribe
    end

    assert_raise RuntimeError do
      r.punsubscribe
    end
  end

  def test_subscribe_past_a_timeout
    # For some reason, a thread here doesn't reproduce the issue.
    sleep = %{sleep #{OPTIONS[:timeout] * 2}}
    publish = %{ruby -rsocket -e 't=TCPSocket.new("127.0.0.1",#{OPTIONS[:port]});t.write("publish foo bar\\r\\n");t.read(4);t.close'}
    cmd = [sleep, publish].join("; ")

    IO.popen(cmd, "r+") do |pipe|
      received = false

      r.subscribe "foo" do |on|
        on.message do |channel, message|
          received = true
          r.unsubscribe
        end
      end

      assert received
    end
  end
end
