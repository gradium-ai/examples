// Keyword stand-in for Jev so the demo runs without a key. It is labelled as
// offline everywhere it shows up; it is not what the article recommends.
const FRUSTRATED = /\b(charged twice|nobody|no one|still|again|refund|annoy|angry|upset|terrible|unacceptable|ridiculous|waited|waiting|broken|worst|never)\b/i;
const ENTHUSIASTIC = /(can'?t wait|love|awesome|amazing|excited|great|thanks so much|!!|yay|fantastic)/i;
const URGENT = /\b(asap|urgent|immediately|right now|now|today|charged|twice|a week|still waiting|emergency)\b/i;

export function offlineAnswers(text: string) {
  const f = FRUSTRATED.test(text);
  const e = !f && ENTHUSIASTIC.test(text);
  const u = URGENT.test(text);
  const tone = f ? "frustrated" : e ? "enthusiastic" : "neutral";
  const toneP = { frustrated: f ? 0.8 : 0.1, neutral: f || e ? 0.1 : 0.8, enthusiastic: e ? 0.8 : 0.1 };
  const energyP = { relaxed: u ? 0.25 : 0.75, urgent: u ? 0.75 : 0.25 };
  return {
    tone: { choice: tone, confidence: 0.7, probabilities: toneP },
    energy: { choice: u ? "urgent" : "relaxed", confidence: 0.65, probabilities: energyP },
  };
}
