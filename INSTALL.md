HOW TO INSTALL LANG5
====================

 Installing lang5 on your system is quite simple and straightforward:

Prerequisites:
--------------
 All you need prior to installing lang5 is a Perl interpreter. Anything from
Perl 5.8.0 will be sufficient (and most probably older Perl interpreters, too,
as long as it is a version 5.x).

UNIX-installation:
-------------

- First you have to decide where to install lang5. There is no need to install
  lang5 into /usr/local or somewhere like that - it can happily live in any 
  user directory, too. Change your working directory to the location you
  chose: 

                cd <path_to_your_lang5>

- Unpack the distribution kit: 

                unzip lang5.zip

- This creates a subdirectory named "lang5" under your current working 
  directory.

- Make the lang5-interpreter executable: 

                chmod 755 lang5/lang5

- Make sure that the lang5-directory is in your PATH-environment variable 
  (otherwise you have to call the interpreter explicitly with an absolute 
  path).  Therefore you might want to extend the .profile in your homedirectory 
  by a line like this:

                export PATH=$PATH:<path_to_your_lang5>

Windows-installation:
---------------------

- Chose a location where you want to UNZIP the distribution package and 
  perform the UNZIP.

- To start the lang5-interpreter, open a command window (cmd.exe) and type

                perl <path_to_your_lang5>/lang5

OpenVMS-installation:
---------------------

- Chose a location where you want to UNZIP the distribution package and 
  perform the UNZIP. For the following example it is assumed that you 
  UNZIPped the lang5-distribution package to the location

                DISK$SOFTWARE:[LANG5]

- Make the directory and its subdirectories read- and executable for world:

$ SET PROT=W:RE DISK$SOFTWARE:[000000]LANG5.DIR
$ SET PROT=W:RE DISK$SOFTWARE:[LANG5...]*.*

- Create a foreign command to call LANG5. Therefore you might want to include
  a line like the following in your user's LOGIN.COM or the system wide 
  SYS$MANAGER:LOGIN.COM:

$ LANG5 :== PERL DISK$SOFTWARE:[LANG5]LANG5
