#!/usr/bin/perl
use strict;
use warnings;

#dependencies - On Windows, use Strawberry Perl to get these built-in
use LWP;
use XML::LibXML;

my $version_string = "1.3";
my $xms_app_name = "app";

if( (@ARGV != 1) || ! ($ARGV[0] =~ /\d+\.\d+\.\d+\.\d+/))
{
   die "Usage: perl xms_rest_helloworld.pl [xms_ip_addr]\n" ;
}
print "XMS RESTful 'Hello World' demo - Version $version_string (using LWP ", $LWP::VERSION, " and LibXML ", XML::LibXML::LIBXML_DOTTED_VERSION, ")\n";

my $xms_url_base = "http://$ARGV[0]:81";

my_event_loop();
print "Event Loop exited. That isn't supposed to happen.\n";

# my_event_loop() - Main event loop - Create a connection to XMS, then poll the event handler URL forever, processing events as they arrive
sub my_event_loop
{
    my $response_content = send_request_to_xms_and_await_response(
        "POST",
        "$xms_url_base/default/eventhandlers?appid=${xms_app_name}",
        '<web_service version="1.0"><eventhandler><eventsubscribe action="add" type="any" resource_id="any" resource_type="any"/></eventhandler></web_service>',
        0 # No chunk handler
        );
    
    my $event_handler_response_parser = XML::LibXML->new();
    my $event_handler_response_doc    = $event_handler_response_parser->parse_string($response_content);
    
    my $event_handler_url = $event_handler_response_doc->findvalue('/web_service/eventhandler_response/@href');
    #check for absolute event handler URI
    if ($event_handler_url =~ /^http/){
        print "Found an event handler response. URI='", $event_handler_url, "'\n" ;
    }
    #check for relative event handler URI
    elsif ($event_handler_url =~ /^\//)
    {
        print "Found an event handler response. URI='", $event_handler_url, "'\n" ;
        $event_handler_url = $xms_url_base . $event_handler_url;
        print "Relative URI so adding base URI to get '", $event_handler_url, "'\n" ;
    }
    else {
        die "No event handler response URI found in initial response from XMS\n" ;
    }
    
    # Now we go into the event loop
    while(1)
    {
        print("Waiting for an event\n");
        send_request_to_xms_and_await_response(
             "GET",
             "$event_handler_url?appid=${xms_app_name}",
             "", #empty content
             \&my_chunk_handler);
        print("Done waiting for an event\n");
    }
}

# my_handle_event() - Subroutine to process a complete event received from XMS. The demo only handles two events:
#     In case of an incoming call, answer it and play a file
#     When play completes, hang up the call (unless it has already been released)
sub my_handle_event
{
    my($xml_event) = @_;
    my $event_parser = XML::LibXML->new();
    my $event_doc    = $event_parser->parse_string($xml_event);
    
    my $event_type = $event_doc->findvalue('/web_service/event/@type');
    my $resource_type = $event_doc->findvalue('/web_service/event/@resource_type');
    my $resource_id = $event_doc->findvalue('/web_service/event/@resource_id');
    my $event_reason = $event_doc->findvalue('/web_service/event/event_data[@name=\'reason\']/@value');

    print "my_handle_event: Got an event of type '$event_type' and resource type '$resource_type' and reason '$event_reason'\n";

    if($event_type eq "incoming")
    {
        print "Incoming call. Answering...\n";
        my $response_content = send_request_to_xms_and_await_response(
            "PUT",
            "$xms_url_base/default/calls/${resource_id}?appid=${xms_app_name}",
            '<web_service version="1.0"><call answer="yes" async_dtmf="yes" async_tone="yes" cpa="no" dtmf_mode="rfc2833" media="audiovideo" rx_delta="+0dB" signaling="yes" tx_delta="+0dB"/></web_service>',
            0 # No chunk handler
            );
        my $call_response_parser = XML::LibXML->new();
        my $call_response_doc    = $call_response_parser->parse_string($response_content);
        if($call_response_doc->findvalue('/web_service/call_response/@connected') eq "yes")
        {
            print "Incoming call connected. Playing...\n";
            my $response_content = send_request_to_xms_and_await_response(
                "PUT",
                "$xms_url_base/default/calls/${resource_id}?appid=${xms_app_name}",
                '<web_service version="1.0"><call><call_action><play delay="0s" max_time="infinite" offset="0s" repeat="0" skip_interval="10s" terminate_digits="9"><play_source location="file://xmstool/xmstool_play"/></play></call_action></call></web_service>',
                0 # No chunk handler
                );
        }
        else
        {
            print "Incoming call not connected. Ignoring incoming call event\n";
        }
    }

    if($event_type eq "end_play")
    {
        if($event_reason eq "hangup")
        {
            print "Play done due to hangup. No action required.\n";
        }
        else
        {
            print "Play done. Hanging up...\n";
            my $response_content = send_request_to_xms_and_await_response(
                "PUT",
                "$xms_url_base/default/calls/${resource_id}?appid=${xms_app_name}",
                '<web_service version="1.0"><call><call_action><hangup/></call_action></call></web_service>',
                0 # No chunk handler
            );
        }
    }
}

# my_chunk_handler() - This callback function is called by the LWP request() function whenever an HTTP chunk is received. The function
#    collects chunks until it has an entire XMS event, and then calls the event handler for further processing.
# Note that this is tuned for the new event format starting in XMS 2.3 SU1 and later. It won't work in XMS 2.3 baseline and earlier.
my $middle_of_an_event = 0;
my $collected_event = "";
my $expected_event_length = 0;
sub my_chunk_handler
{
    my($data, $response_obj, $protocl_obj) = @_;

    #save the length (hexidecimal) on a line of its own if it's at the start of an event
    if(! $middle_of_an_event)
    {
        $data =~ s/^([[:xdigit:]]+)\r\n//;
        if(defined($1))
        {
            $expected_event_length = hex($1);
        }
        else
        {
            print "Event did not start with hex length value. Dropping it : '$data' \n";
            return 1;
        }
    }

    #add the new data to any data already collected for this event, and process the event if the entire event is collected
    $collected_event = $collected_event . $data;
    if(length($collected_event) >= $expected_event_length)
    {
        print("Got an event - advertised_len=$expected_event_length - received_len=" . length($collected_event) . "\n$collected_event\n----------\n");
        my_handle_event($collected_event);

        $middle_of_an_event = 0;
        $collected_event = "";
        $expected_event_length = 0;
    }
    else
    {
        $middle_of_an_event = 1;
    }
    return 1;
}

#send_request_to_xms_and_await_response() - Subroutine used for both polling the XMS for events and sending commands to XMS and
#    waiting for the response to the command.
sub send_request_to_xms_and_await_response
{
    my ($method, $url, $content, $chunk_handler) = @_;

    $method = uc($method);
    
    if($content)
    {
        print "----------\nSending HTTP $method for '$url' with content:\n$content\n----------\n";
    }
    else
    {
        print "----------\nSending HTTP $method for '$url'\n----------\n";
    }
    
    my $req;
    if($method eq "POST")
    {
        $req = HTTP::Request->new(POST => $url);
    }
    elsif($method eq "GET")
    {
        $req = HTTP::Request->new(GET => $url);
    }
    elsif($method eq "PUT")
    {
        $req = HTTP::Request->new(PUT => $url);
    }
    else
    {
        print "Unrecognized method '$method' in send_request_to_xms_and_await_response(). Skipping\n";
        return "";
    }

    $req->content_type('application/xml');
    $req->content($content);
    
    # Pass request to the user agent and get a response back
    my $ua = LWP::UserAgent->new;
    $ua->agent("xms_rest_helloworld/$version_string");

    my $res;
    if(ref($chunk_handler) eq "CODE")
    {
        $ua->timeout(20*60); # 20-minute timeout for the event handler
        $res = $ua->request($req, $chunk_handler);
    }
    else
    {
        $ua->timeout(2); # 2-second timeout for the regular requests
        $res = $ua->request($req);
    }

    # Check the outcome of the response
    if ($res->is_success) {
        print "Received response from XMS - ", $res->status_line, ":\n",$res->content;
    }
    else {
        print "HTTP $method Failed: ", $res->status_line, ":\n";
        print $res->content;
    }
    return $res->content;
}
