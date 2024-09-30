
import drop.*;
SDrop drop;

import javax.sound.midi.*;
import java.io.File;
import java.util.ArrayList;

ArrayList<Note> notes = new ArrayList<Note>();
ArrayList<Note> processedNotes = new ArrayList<Note>();

Sequence sequence;

void setup() {
  size(500, 500);
  drop = new SDrop(this);
}

void draw() {
  background(0);
  text("drop midi file", 50, 50);
  text("output will appear in the data folder", 50, 100);
}

void dropEvent(DropEvent theDropEvent) {

  if (theDropEvent.isFile()) {

    processMidiFile(new File(theDropEvent.filePath()));

    int maxTick = 0;
    for (Note note : notes) {
      maxTick = max(maxTick, note.stopTick+1);  // Get max tick for iteration bounds
    }

    // Initialize layer counter
    int layer = 0;

    // Continue processing until all notes have been assigned a layer
    while (notes.size() > 0) {
      // Iterate through ticks from 0 to maxTick
      for (int currentTick = 0; currentTick < maxTick; currentTick++) {

        // Find the highest note playing at the current tick
        Note highestNote = findHighestNoteAtTick(currentTick);
        if (highestNote != null) {
          highestNote.layer = layer;  // Assign layer to the note
          currentTick = highestNote.stopTick - 1;  // Skip to the end of the current note

          // Remove the note from the notes array (it has been processed)
          processedNotes.add(highestNote);
          notes.remove(highestNote);
        }
      }
      layer++;  // Move to the next layer for the next set of notes
    }

    for (Note note : processedNotes) {
      println(note.note+" "+note.velocity+" "+note.channel+" "+note.startTick+" "+note.stopTick+" "+note.layer);
    }

    // Convert the modified notes back to MIDI and save the file
    saveAsMidi(processedNotes, sequence);

    exit();
  }
}

void saveAsMidi(ArrayList<Note> notes, Sequence originalSequence) {
  try {
    int ppq = originalSequence.getResolution();  // Use the original PPQ resolution

    // Find the maximum layer to determine how many files we need
    int maxLayer = 0;
    for (Note note : notes) {
      maxLayer = max(maxLayer, note.layer);
    }

    // Create and save a separate MIDI file for each layer
    for (int layer = 0; layer <= maxLayer; layer++) {
      Sequence sequence = new Sequence(Sequence.PPQ, ppq);  // Match the original sequence's PPQ
      Track track = sequence.createTrack();  // Create a track for the layer

      // Copy the tempo events from the original sequence
      Track originalTrack = originalSequence.getTracks()[0];  // Assuming tempo is in the first track
      for (int i = 0; i < originalTrack.size(); i++) {
        MidiEvent event = originalTrack.get(i);
        MidiMessage message = event.getMessage();

        if (message instanceof MetaMessage) {
          MetaMessage metaMsg = (MetaMessage) message;
          if (metaMsg.getType() == 0x51) {  // Tempo MetaMessage (0x51 is the tempo change message type)
            track.add(new MidiEvent(metaMsg, event.getTick()));  // Copy tempo change
          }
        }
      }

      // Add NOTE_ON and NOTE_OFF events for the current layer
      for (Note note : notes) {
        if (note.layer == layer) {
          // Create NOTE_ON event
          ShortMessage noteOnMessage = new ShortMessage();
          noteOnMessage.setMessage(ShortMessage.NOTE_ON, note.channel, note.note, note.velocity);
          MidiEvent noteOnEvent = new MidiEvent(noteOnMessage, note.startTick);
          track.add(noteOnEvent);

          // Create NOTE_OFF event
          ShortMessage noteOffMessage = new ShortMessage();
          noteOffMessage.setMessage(ShortMessage.NOTE_OFF, note.channel, note.note, 0);  // velocity 0 for NOTE_OFF
          MidiEvent noteOffEvent = new MidiEvent(noteOffMessage, note.stopTick);
          track.add(noteOffEvent);
        }
      }

      // Save the sequence for the current layer
      File outputFile = new File(dataPath("output_layer_" + layer + ".mid"));
      MidiSystem.write(sequence, 1, outputFile);
      println("Layer " + layer + " saved as: " + outputFile.getAbsolutePath());
    }

  } catch (Exception e) {
    e.printStackTrace();
  }
}

// Function to find the highest note playing at a given tick
Note findHighestNoteAtTick(int currentTick) {
  Note highestNote = null;

  // Iterate over remaining notes to find the highest note that starts at or before the current tick
  for (Note note : notes) {
    if (note.startTick <= currentTick && note.stopTick > currentTick) {
      if (highestNote == null || note.note > highestNote.note) {
        highestNote = note;  // Update if this note is higher
      }
    }
  }
  return highestNote;
}

void processMidiFile(File midiFile) {
  try {
    sequence = MidiSystem.getSequence(midiFile);
    for (Track track : sequence.getTracks()) {
      processTrack(track);
    }
  }
  catch (Exception e) {
    e.printStackTrace();
  }
}

void processTrack(Track track) {
  for (int i = 0; i < track.size(); i++) {
    MidiEvent event = track.get(i);
    MidiMessage message = event.getMessage();

    if (message instanceof ShortMessage) {
      ShortMessage sm = (ShortMessage) message;
      long tick = event.getTick();  // Get the tick time of the event

      if (sm.getCommand() == ShortMessage.NOTE_ON) {
        int note = sm.getData1();
        int velocity = sm.getData2();

        if (velocity > 0) {
          // Create and add the Note object to the ArrayList
          notes.add(new Note(note, velocity, sm.getChannel(), tick, -1)); // stopTick is -1 for now
        } else {
          // Handle NOTE_OFF using a NOTE_ON with velocity 0
          closeNote(note, tick);
        }
      } else if (sm.getCommand() == ShortMessage.NOTE_OFF) {
        int note = sm.getData1();
        closeNote(note, event.getTick());
      }
    }
  }
}

// Closes the note when NOTE_OFF is encountered by setting stopTick
void closeNote(int noteValue, long stopTick) {
  for (Note note : notes) {
    if (note.note == noteValue && note.stopTick == -1) {
      note.stopTick = (int) stopTick; // Update stopTick when the note is released
      break;
    }
  }
}

// Note class to hold the note data
class Note {
  int note;
  int velocity;
  int channel;
  int startTick;
  int stopTick;
  int layer = -1;

  Note(int note, int velocity, int channel, long startTick, long stopTick) {
    this.note = note;
    this.velocity = velocity;
    this.channel = channel;
    this.startTick = (int) startTick;
    this.stopTick = (int) stopTick;
  }
}
