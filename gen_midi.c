/*
 
 Create Midifile  example for  libJDKSmidi C++ MIDI Library
 
 Copyright (C) 2010 V.R.Madgazin
 www.vmgames.com
 vrm@vmgames.com
 
 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 2
 of the License, or (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program;
 if not, write to the Free Software Foundation, Inc.,
 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 
 */

#ifdef WIN32
#include <windows.h>
#endif

#include "jdksmidi/world.h"
#include "jdksmidi/track.h"
#include "jdksmidi/multitrack.h"
#include "jdksmidi/filereadmultitrack.h"
#include "jdksmidi/fileread.h"
#include "jdksmidi/fileshow.h"
#include "jdksmidi/filewritemultitrack.h"
#include "ryc.h"
using namespace jdksmidi;

#include <iostream>
using namespace std;

int toSemi (struct nodeType *num) {
  double full = num->num.value;
  // rest
  if (full == 0)
    return -1;
  
  int semi = 60 + num->num.vary;
  while (full > 7) {
    full -= 7;
    semi += 12;
  }
  while (full < 1) {
    full += 7;
    semi -= 12;
  }

  if (full == 1) {
    
  } else if (full == 2) {
    semi += 2;
  } else if (full == 3) {
    semi += 4;
  } else if (full == 4) {
    semi += 5;
  } else if (full == 5) {
    semi += 7;
  } else if (full == 6) {
    semi += 9;
  } else if (full == 7) {
    semi += 11;
  } else {
    printf("Invalid pitch");
    exit(1);	/* cannot continue */
  }
  
  if (semi < 0) {
    printf("too low pitch\n");
    exit(1);
  }
  
  return semi;
}

int play(struct nodeType *r,
         int current_t,
         int base,
         int chan,
         MIDITimedBigMessage &m,
         MIDIMultiTrack &tracks) {
  int t, note, velocity, trk = 1, dt = 100;
  if (r->mld.combineType == seq) {
    struct nodeType *mld = r;
    while (mld && mld->mld.body) {
      if (mld->mld.body->type == typeNote) {
        int semi = toSemi(mld->mld.body->note.pitch);
        double duration = mld->mld.body->note.duration->num.value;
        if (semi != -1) {
          m.SetTime( t = current_t );
          m.SetNoteOn( chan, note = base + semi, velocity = 100 );
          tracks.GetTrack( trk )->PutEvent( m );
        }
        t += dt * duration;
        if (semi != -1) {
          m.SetTime( t );
          m.SetNoteOff( chan, note, velocity );
          tracks.GetTrack( trk )->PutEvent( m );
        }
        current_t = t;
      } else {
        current_t = play(mld->mld.body, current_t, base, chan, m, tracks);
      }
      mld = mld->mld.next;
    }
  } else {
    struct nodeType *mld = r;
    int max_t = current_t;
    while (mld && mld->mld.body) {
      if (mld->mld.body->type == typeNote) {
        int semi = toSemi(mld->mld.body->note.pitch);
        double duration = mld->mld.body->note.duration->num.value;
        if (semi != -1) {
          m.SetTime( t = current_t );
          m.SetNoteOn( chan, note = base + semi, velocity = 100 );
          tracks.GetTrack( trk )->PutEvent( m );
        }
        t += dt * duration;
        if (semi != -1) {
          m.SetTime( t );
          m.SetNoteOff( chan, note, velocity );
          tracks.GetTrack( trk )->PutEvent( m );
        }
      } else {
        t = play(mld->mld.body, current_t, base, chan, m, tracks);
      }
      if (max_t < t)
        max_t = t;
      mld = mld->mld.next;
      chan++;
    }
    current_t = max_t;
  }
  return current_t;
}

// number of ticks in crotchet (1...32767)
int gen_midi (struct nodeType *tempo,
              struct nodeType *key,
              struct nodeType *song)
{
  int base = toSemi(key) - 60;
  int clks_per_beat = (int)(tempo->num.value);
  if (clks_per_beat < 1) {
    printf("Invalid tempo specified. Changing to default 120.\n");
    clks_per_beat = 120;
  }

  
  int return_code = -1;
  
  MIDITimedBigMessage m; // the object for individual midi events
  unsigned char chan, // internal midi channel number 0...15 (named 1...16)
  note, velocity, ctrl, val;
  
  MIDIClockTime t; // time in midi ticks
  MIDIClockTime dt = 100; // time interval (1 second)
   
  int num_tracks = 2; // tracks 0 and 1
  
  MIDIMultiTrack tracks( num_tracks );  // the object which will hold all the tracks
  tracks.SetClksPerBeat( clks_per_beat );

  int trk; // track number, 0 or 1
  
  t = 0;
  m.SetTime( t );
  
  // track 0 is used for tempo and time signature info, and some other stuff
  
  trk = 0;
  
  /*
   SetTimeSig( numerator, denominator_power )
   The numerator is specified as a literal value, the denominator_power is specified as (get ready!)
   the value to which the power of 2 must be raised to equal the number of subdivisions per whole note.
   
   For example, a value of 0 means a whole note because 2 to the power of 0 is 1 (whole note),
   a value of 1 means a half-note because 2 to the power of 1 is 2 (half-note), and so on.
   
   (numerator, denominator_power) => musical measure conversion
   (1, 1) => 1/2
   (2, 1) => 2/2
   (1, 2) => 1/4
   (2, 2) => 2/4
   (3, 2) => 3/4
   (4, 2) => 4/4
   (1, 3) => 1/8
   */
  
  m.SetTimeSig( 4, 4 ); // measure 4/4 (default values for time signature)
  tracks.GetTrack( trk )->PutEvent( m );
  
  // int tempo = 1000000; // set tempo to 1 000 000 usec = 1 sec in crotchet
  // with value of clks_per_beat (100) result 10 msec in 1 midi tick
  // If no tempo is define, 120 beats per minute is assumed.
  
  // m.SetTime( t ); // do'nt need, because previous time is not changed
  m.SetTempo( 1000000 );
  tracks.GetTrack( trk )->PutEvent( m );
  
  // META_TRACK_NAME text in track 0 music notation software like Sibelius uses as headline of the music
  tracks.GetTrack( trk )->PutTextEvent(t, META_TRACK_NAME, "LibJDKSmidi create_midifile.cpp example by VRM");
  
  // create cannal midi events and add them to a track 1
  
  trk = 1;
  
  // META_TRACK_NAME text in tracks >= 1 Sibelius uses as instrument name (left of staves)
  tracks.GetTrack( trk )->PutTextEvent(t, META_TRACK_NAME, "Church Organ");
  
  // we change panorama in channels 0-2
  
  m.SetControlChange ( chan = 0, ctrl = 0xA, val = 0 ); // channel 0 panorama = 0 at the left
  tracks.GetTrack( trk )->PutEvent( m );
  
  m.SetControlChange ( chan = 1, ctrl, val = 64 ); // channel 1 panorama = 64 at the centre
  tracks.GetTrack( trk )->PutEvent( m );
  
  m.SetControlChange ( chan = 2, ctrl, val = 127 ); // channel 2 panorama = 127 at the right
  tracks.GetTrack( trk )->PutEvent( m );
  
  // we change musical instrument in channels 0-2
  
  m.SetProgramChange( chan = 0, val = 0 ); // channel 0 instrument 19 - Church Organ
  tracks.GetTrack( trk )->PutEvent( m );
  
  m.SetProgramChange( chan = 1, val = 0 );
  tracks.GetTrack( trk )->PutEvent( m );
  
  m.SetProgramChange( chan = 2, val = 0 );
  tracks.GetTrack( trk )->PutEvent( m );
  
  m.SetProgramChange( chan = 3, val = 0 );
  tracks.GetTrack( trk )->PutEvent( m );
  
  // create individual midi events with the MIDITimedBigMessage and add them to a track 1
  
  t = 0;
  
  t = play(song, t, base, 0, m, tracks);
  
  /*
  // we add note 1: press and release in (dt) ticks
  
  m.SetTime( t );
  m.SetNoteOn( chan = 0, note = 62, velocity = 100 );
  tracks.GetTrack( trk )->PutEvent( m );
  
  // after note(s) on before note(s) off: add words to music in the present situation
  tracks.GetTrack( trk )->PutTextEvent(t, META_LYRIC_TEXT, "Left");
  
  m.SetTime( t += dt );
  m.SetNoteOff( chan, note, velocity );
  // alternative form of note off event: useful to reduce midifile size if running status is used (on default so)
  // m.SetNoteOn( chan, note, 0 );
  tracks.GetTrack( trk )->PutEvent( m );
  
  // note 2
  
  m.SetNoteOn( chan = 1, note = 65, velocity );
  tracks.GetTrack( trk )->PutEvent( m );
  
  tracks.GetTrack( trk )->PutTextEvent(t, META_LYRIC_TEXT, "Centre");
  
  m.SetTime( t += dt );
  m.SetNoteOff( chan, note, velocity );
  tracks.GetTrack( trk )->PutEvent( m );
  
  // note 3
  
  m.SetNoteOn( chan = 2, note = 69, velocity );
  tracks.GetTrack( trk )->PutEvent( m );
  
  tracks.GetTrack( trk )->PutTextEvent(t, META_LYRIC_TEXT, "Right");
  
  m.SetTime( t += dt );
  m.SetNoteOff( chan, note, velocity );
  tracks.GetTrack( trk )->PutEvent( m );
  
  // add pause
  
  t += dt;
  
  // add chord: 3 notes simultaneous
  
  // press
  m.SetTime( t );
  m.SetNoteOn( chan = 0, note = 62, velocity );
  tracks.GetTrack( trk )->PutEvent( m );
  m.SetNoteOn( chan = 1, note = 65, velocity );
  tracks.GetTrack( trk )->PutEvent( m );
  m.SetNoteOn( chan = 2, note = 69, velocity );
  tracks.GetTrack( trk )->PutEvent( m );
  
  tracks.GetTrack( trk )->PutTextEvent(t, META_LYRIC_TEXT, "Chord");
  
  // release
  m.SetTime( t += (2*dt) );
  m.SetNoteOff( chan = 0, note = 62, velocity );
  tracks.GetTrack( trk )->PutEvent( m );
  m.SetNoteOff( chan = 1, note = 65, velocity );
  tracks.GetTrack( trk )->PutEvent( m );
  m.SetNoteOff( chan = 2, note = 69, velocity );
  tracks.GetTrack( trk )->PutEvent( m );
  */
   
  // add pause: press note with velocity = 0 equivalent to simultaneous release it
  
  t += dt;
  m.SetTime( t );
  m.SetNoteOn( chan = 0, note = 0, velocity = 0 );
  tracks.GetTrack( trk )->PutEvent( m );
   
  
  // if events in any track recorded not in order of the growth of time,
  tracks.SortEventsOrder(); // it is necessary to do this before write step
  
  // to write the multi track object out, you need to create an output stream for the output filename
  
  const char *outfile_name = "a.mid";
  MIDIFileWriteStreamFileName out_stream( outfile_name );
  
  // then output the stream like my example does, except setting num_tracks to match your data
  
  if( out_stream.IsValid() )
  {
    // the object which takes the midi tracks and writes the midifile to the output stream
    MIDIFileWriteMultiTrack writer( &tracks, &out_stream );
    
    // write the output file
    if ( writer.Write( num_tracks ) )
    {
      cout << "\nOK writing file " << outfile_name << endl;
      return_code = 0;
    }
    else
    {
      cerr << "\nError writing file " << outfile_name << endl;
    }
  }
  else
  {
    cerr << "\nError opening file " << outfile_name << endl;
  }
  
  return return_code;
}

