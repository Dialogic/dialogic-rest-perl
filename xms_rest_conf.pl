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
   die "Usage: perl xms_rest_conf.pl [xms_ip_addr]\n" ;
}
print "XMS RESTful conferncing demo - Version $version_string (using LWP ", $LWP::VERSION, " and LibXML ", XML::LibXML::LIBXML_DOTTED_VERSION, ")\n";

my $xms_url_base = "http://$ARGV[0]:81";
my $global_conf_id;

my_delete_exiting_conferences();
my_create_conference();

my_event_loop();
print "Event Loop exited. That isn't supposed to happen.\n";

sub my_delete_exiting_conferences
{
    print "Getting list of existing conferences...\n";
    my $response_content = send_request_to_xms_and_await_response(
        "GET",
        "$xms_url_base/default/conferences?appid=${xms_app_name}",
        "", # empty payload for getting conference list
        0 # No chunk handler
        );
    my $conf_response_parser = XML::LibXML->new();
    if($response_content)
    {
        my $conf_response_doc    = $conf_response_parser->parse_string($response_content);
        for my $conference_response ($conf_response_doc->findnodes('/web_service/conferences_response/conference_response'))
        {
            my ($conf_id) = $conference_response->findvalue('@identifier');
            print("Found an existing conference with ID $conf_id. Deleting...\n");
            send_request_to_xms_and_await_response(
                "DELETE",
                "$xms_url_base/default/conferences/${conf_id}?appid=${xms_app_name}",
                "", # empty payload for deleting conference
                0 # No chunk handler
                );
        }
    }
}

sub my_create_conference
{
    print "Creating Conference...\n";
    my $response_content = send_request_to_xms_and_await_response(
        "POST",
        "$xms_url_base/default/conferences?appid=${xms_app_name}",
        '<web_service version="1.0"><conference type="audiovideo" max_parties="4" reserve="2" layout="4" caption="yes" caption_duration="580s" beep="yes" clamp_dtmf="yes" auto_gain_control="yes" echo_cancellation="yes"/></web_service>',
        0 # No chunk handler
        );
    my $conference_response_parser = XML::LibXML->new();
    if($response_content)
    {
        my $conference_response_doc    = $conference_response_parser->parse_string($response_content);
        $global_conf_id = $conference_response_doc->findvalue('/web_service/conference_response/@identifier');
        if($global_conf_id ne "")
        {
            print "Conference ID is $global_conf_id\n";
        }
        else
        {
            print "ERROR: Didn't get conference ID\n";
        }
    }
}

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

# my_handle_event() - Subroutine to process a complete event received from XMS. The demo only handles one event:
#     In case of an incoming call, answer it and join it to the conference

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
        print("Handling call response 1\n");
        if($call_response_doc->findvalue('/web_service/call_response/@connected') eq "yes")
        {
            print("Handling call response 2\n");
            my $caller_name = $call_response_doc->findvalue('/web_service/call_response/@source_uri');
            $caller_name =~ s/rtc://;
            $caller_name =~ s/sip:(\w+).*/$1/;

            print "Incoming call from '$caller_name' connected. Joining to conference...\n";
            my $response_content = send_request_to_xms_and_await_response(
                "PUT",
                "$xms_url_base/default/calls/${resource_id}?appid=${xms_app_name}",
                '<web_service version="1.0"><call><call_action><add_party conf_id="' . $global_conf_id . '" caption="' . $caller_name . '" region="0" audio="sendrecv" video="sendrecv"/></call_action></call></web_service>',
                0 # No chunk handler
                );
        }
        else
        {
            print "Incoming call not connected. Ignoring incoming call event\n";
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
    elsif($method eq "DELETE")
    {
        $req = HTTP::Request->new(DELETE => $url);
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
    $ua->agent("xms_rest_conf/$version_string");

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
        print "$method : Received response from XMS - ", $res->status_line, ":\n",$res->content;
    }
    else {
        print "HTTP $method Failed: ", $res->status_line, ":\n";
        print $res->content;
    }
    return $res->content;
}
