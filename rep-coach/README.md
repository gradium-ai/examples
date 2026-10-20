# RepCoach

An iPhone rep counter for the gym that works with no network. Prop the phone up and the front
camera watches you. It counts each rep out loud, encourages you near your target, splits sets
on its own when you rest, and speaks a summary at the end. Pose detection is Apple Vision and
the voice is Phonon on the Neural Engine. Nothing leaves the phone.

Exercises: squat (Smith/barbell), pull-up, lat pulldown, push-up, lunge, Romanian deadlift,
crunch, and a standing arm raise for trying the app out anywhere.

## Layout

| | |
|---|---|
| `RepCoachCore/` | The counting logic as a Swift package. No camera or audio, so it builds and runs on a Mac. |
| `RepCoach/` | The iOS app: camera + Vision, Phonon voice, SwiftUI screens, SwiftData history. |
| `project.yml` | XcodeGen spec. `RepCoach.xcodeproj` is generated from it, not committed. |
| `Models/` | The Core ML Phonon 31M voice model (~160 MB, not committed), from `scripts/fetch-model.sh`. |

## How a rep is counted

Each exercise turns the pose into a 0–1 "how deep into the rep" signal:

- **Squat:** how far the hip has dropped towards the knee. This works front-on, where the knee
  angle barely changes because the thigh points at the camera. Facing the phone, perspective
  makes the knees look lower than they are at the bottom (they come towards the lens while the
  hips go back), so a squat just above parallel reads about 0.73 instead of 0.9; when the
  shoulders show the body facing the phone, the deep part of the reading is raised to match.
- **Pull-up:** how far the nose is below the hands. It reaches 1 with the chin at the bar and
  counts there.
- **Lat pulldown:** how far the hands are above the shoulders. This works from in front or behind.
- **Push-up:** the elbow angle, seen side-on.
- **Arm raise:** how high the lower hand is above the shoulders, in torso lengths, so both
  arms have to go overhead.
- **Lunge:** how far the hip has dropped towards the front knee, the knee nearest the hip, since
  the back knee drops towards the floor. Alternating legs count one each.
- **Romanian deadlift:** how far the torso (shoulder to hip) has tipped from upright, or, seen
  from the front where the tilt hardly shows, how much shorter it looks.
- **Crunch:** the angle the torso rises off the floor, measured from its resting angle, lying
  side-on to the phone.

The rest distance (standing hip height, dead-hang reach) is learned live. It follows you if you
step closer to or further from the phone between sets, and when you stand still at a shallow
reading for most of a second it is relearned quickly, so a distance learned while closer to the
phone cannot leave standing reading as a quarter-squat and merge two reps into one.

A rep counts after the signal leaves rest, reaches the peak threshold and returns to rest
(squat, push-up, arm raise, lunge, Romanian deadlift). Pull-ups, lat pulldowns and crunches
count at the peak instead, the hardest point of the rep, and must return to rest before the
next one can count. Both thresholds must hold for two
frames, and the gap between them stops jitter from double counting. Turning back early is a
partial rep: it is shown on screen and not counted. A set closes after 10 s without movement
(adjustable). A lone stray rep between sets is discarded.

## Form feedback

`FormCheck` (in `RepCoachCore`) measures each rep at its true bottom and only judges what the
camera's angle shows. Each check follows published coaching guidance:

| Exercise | Fault | Seen from | Guidance |
|---|---|---|---|
| Squat | Knees caving in: knee spread narrows against ankle spread compared with standing | Front | NSCA: knees track over the toes; NASM squat assessment |
| Squat | Torso leans 25° or more past the shins | Side | NASM: trunk parallel to the shin |
| Romanian deadlift | Knee angle under 115° at the bottom (a squat, not a hinge) | Side | NSCA: knees stay slightly flexed as the hips move back |
| Push-up | Hips bend the shoulder–hip–ankle line by 20° or more (sag or pike) | Side | NASM: straight line from head to heel |
| Pull-up | Arms not straight at the bottom | Any | Pull-up test standards: chin to the bar, arms fully extended |
| All | Two or more short reps in a set; last reps much shallower than the first | Any | Depth targets above; ACE: lunge to front thigh parallel |

A back that rounds is not judged: Vision has no points along the spine. Tempo is not judged
either: the current ACSM position stand does not prescribe one.

Every squat attempt is checked, not only counted reps: partial reps, and quarter squats that
never reach the counter's start (0.4) as long as the feet stay planted, which also count as
short reps within a set. Knees caving in is judged over the whole movement, on at least two
frames, against the knee spread learned while standing upright. A fault is said the first
time it shows ("Push your knees out."), once per workout, and each time it shows the rep's
bones turn red with a label for a moment. "Go deeper on your last reps" only comes when the
last reps barely made the counting depth. After each set the coach says at most
three short sentences ("Keep your knees in line with your toes."), or one of praise for a clean
set, and shows them while you rest; the workout summary lists them. On the 19 clips in
`scripts/video-clips.tsv` and the gym recordings no fault is raised: coaches' RDLs bottom out at
135–155° at the knee, and the recorded front-on squats push the knees out (knee spread from
0.7 to 1.3–1.4 times the ankle spread).

## Getting into position

While you set up, `Positioning` (in `RepCoachCore`) reads each frame and picks one direction:
step into view, step back, come closer, move left or right (said as your left or right when you
face the phone, forwards or backwards when side-on), turn to face the phone (pull-ups, pulldowns,
arm raises), turn sideways (lunges: facing the phone a lunge barely registers), lie down side-on, or
"I can't see your knees". The app shows it as a large card with an arrow and a glow on the edge
of the picture you are running off, and says it out loud once it has held for half a second.
Once you hold still in position, it counts down from three and starts on its own (Settings →
Start when I'm in position; "Start now" skips the wait). `repcoach-replay --guide` prints the
directions a recording or video would get.

Thresholds live in `Exercise.thresholds` (`RepCoachCore/Sources/RepCoachCore/Exercise.swift`).

## Build

You need Xcode 26+ (iOS 18 SDK or later) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
Phonon comes from an [xn-ptts](https://github.com/gradium-ai/xn-ptts) release, so there is nothing
to compile outside Xcode.

```bash
# 1. The voice model: Phonon 31M as Core ML, from the xn-ptts release, into Models/
scripts/fetch-model.sh

# 2. The Xcode project. Swift Package Manager fetches the PhononTTS package on first open.
xcodegen
open RepCoach.xcodeproj
```

`Models/` holds [Phonon 31M](https://huggingface.co/gradium/phonon-31m-en) as Core ML. The weights
are not committed. Without them (keep
`Models/README.md`) the app still builds and runs, and counts with the iOS system voice instead
of Phonon. The coach speaks with Harper by default; Settings offers the other 24 English voices.

In Xcode, pick your team under Signing & Capabilities. A free Apple ID works, but the app expires
after 7 days and needs reinstalling. Plug in the iPhone and Run. On the first launch the
voice is compiled for the phone and every count and phrase is synthesized once. This takes a
little while; later launches are quick.

## Checks and replay

```bash
cd RepCoachCore
swift run repcoach-check     # counting checks on synthetic movement
swift run repcoach-replay ~/Downloads/2026-10-06-183000-squat.jsonl --trace --expect 10,10,8
```

`scripts/video-check.sh` runs the counter on real videos of other people: it fetches the
YouTube clips in `scripts/video-clips.tsv` (needs `yt-dlp` and `ffmpeg`), runs Vision on them
with `repcoach-video` and compares the count with a hand count. Currently 16 of 19 clips count
exactly. The three misses are footage the app can't fix, and they are kept as reminders:
barbell Romanian deadlifts filmed straight side-on, where the plates hide the hips at lockout,
and a dim 640×480 lunge clip that loses the body at the bottom.

Turn on **Settings → Record pose data** in the app to save each workout's joints (never video)
to `Recordings` in the Files app. To get them onto the Mac, use AirDrop, or Finder → iPhone →
Files → RepCoach. Then run `repcoach-replay` on them. `--trace` prints the signal frame by
frame, and `--expect` turns a recording into a regression check.

## Privacy

- **No network.** The app has no networking code.
- **No video is saved.** Camera frames go to Vision for pose detection and are then discarded.
- **Workout history** (date, exercise, reps per set) is stored on the phone with SwiftData.
- **Pose recordings** are off by default. When turned on, they save joint positions only, never
  images, to `Documents/Recordings`. They are encrypted while the phone is locked and can be
  read through Finder and the Files app, so you can copy them off the phone.

## License

Third-party code and its licenses are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
