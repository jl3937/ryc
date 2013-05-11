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
#include <algorithm>
using namespace std;

const static double o = 1e-8;
const static double oo = 1e+8;
const static int numChannels = 5;

struct intervalType {
  intervalType(double s, double e, int n): start(s), end(e), note(n), channel(-1) {}
  bool operator<(const intervalType &second) const {
    return start < second.start - o;
  }
  double start, end;
  int note;
  int channel;
};

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

double constructIntervals(struct nodeType *r, int base, double current,
                          vector<intervalType> &intervals) {
  if (r->type == typeNote) {
    double duration = r->note.duration->num.value * 100;
    int semi = toSemi(r->note.pitch);
    if (semi != -1) {
      intervals.push_back(intervalType(current,
                                       current + duration,
                                       base + semi));
    }
    return duration;
  }
  if (r->mld.combineType == seq) {
    double oldCurrent = current;
    struct nodeType *mld = r;
    while (mld) {
      if (mld->mld.body)
        current += constructIntervals(mld->mld.body, base, current, intervals);
      mld = mld->mld.next;
    }
    return current - oldCurrent;
  }
  if (r->mld.combineType == par) {
    struct nodeType *mld = r;
    double maxDuration = 0;
    while (mld) {
      if (mld->mld.body) {
        maxDuration = max(maxDuration,
                          constructIntervals(mld->mld.body, base, current, intervals));
      }
      mld = mld->mld.next;
    }
    return maxDuration;
  }
  assert(0 && "unknown combineType");
}

double constructMidi(struct nodeType *song, int base,
                   MIDITimedBigMessage &msg, MIDIMultiTrack &tracks) {
  vector<intervalType> intervals;
  double duration = constructIntervals(song, base, 0, intervals);

  sort(intervals.begin(), intervals.end());
#if 0
  fprintf(stderr, "==============\n");
  for (size_t i = 0; i < intervals.size(); ++i)
    fprintf(stderr, "%.3lf %.3lf\n", intervals[i].start, intervals[i].end);
  fprintf(stderr, "==============\n");
#endif

  double occupiedTo[numChannels];
  for (int i = 0; i < numChannels; ++i)
    occupiedTo[i] = 0;
  for (size_t i = 0; i < intervals.size(); ++i) {
    double maxOccupiedTo = -oo;
    int maxJ = -1;
    for (int j = 0; j < numChannels; ++j) {
      if (occupiedTo[j] <= intervals[i].start + o &&
          maxOccupiedTo < occupiedTo[j] - o) {
        maxOccupiedTo = occupiedTo[j];
        maxJ = j;
      }
    }
    assert(maxJ != -1 && "not enough channels");
    intervals[i].channel = maxJ;
    occupiedTo[maxJ] = intervals[i].end;
  }

  for (size_t i = 0; i < intervals.size(); ++i) {
    assert(intervals[i].channel != -1);
    msg.SetTime((unsigned long)(intervals[i].start + 0.5));
    msg.SetNoteOn(intervals[i].channel, intervals[i].note, 100);
    tracks.GetTrack(1)->PutEvent(msg);
    msg.SetTime((unsigned long)(intervals[i].end + 0.5));
    msg.SetNoteOff(intervals[i].channel, intervals[i].note, 100);
    tracks.GetTrack(1)->PutEvent(msg);
  }

  return duration;
}

// number of ticks in crotchet (1...32767)
int gen_midi(struct nodeType *tempo,
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
  note, velocity;
  
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
  
  // we change musical instrument in channels 0-2
  
  for (int chan = 0; chan < numChannels; ++chan) {
    m.SetProgramChange(chan, 0 ); // channel 0 instrument 19 - Church Organ
    tracks.GetTrack(1)->PutEvent(m);
  }

  // create individual midi events with the MIDITimedBigMessage and add them to a track 1
  
  t = 0;
  
  t = constructMidi(song, base, m, tracks);
  
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

