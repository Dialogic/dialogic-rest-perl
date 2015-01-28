![alt tag](https://www.dialogic.com/~/media/shared/graphics/video/nwrkfuel-posterimg.jpg)

Dialogic PowerMedia XMS
=======================
Dialogic’s PowerMedia™ XMS is a powerful next-generation software media server that enables standards-based, real-time multimedia communications solutions for mobile and broadband environments. PowerMedia XMS supports standard media control interfaces such as MSML, VXML, NetAnn, and JSR 309, plus a Dialogic HTTP-based version of a RESTful API.


dialogic-rest-perl
==================
Overview: A PERL script based repository using the PowerMedia XMS RESTful API which provides application developers using RESTful API over http transport to control media and call control resources of PowerMedia XMS.


Repository Contents
===================
**xms_rest_helloworld.pl** - simple script that waits for an incoming call and plays a file

**xms_rest_conf.pl** - creates a single conference and joins incoming callers to the conference

Usage: perl scriptname XMS_IP_Addr

Dependencies: modules LWP and XML::LibXML, which come with Strawberry Perl on Windows, and can be grabbed from CPAN if needed on Linux

Note - all scripts have been developed and tested using XMS 2.3 SU1. 

Useful Links
=============
For more information, visit the  PowerMedia XMS REST Reference Guide found on in the documents section: http://www.dialogic.com/en/products/media-server-software/xms.aspx

For technical questions, visit our forums:http://www.dialogic.com/den/developer_forums/f/default.aspx



