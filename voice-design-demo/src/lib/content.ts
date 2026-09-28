import type { Language, Register, Tone } from "@/lib/pipeline/types";

// The three messages the demo showcases, written per language and register.
type Localized = Record<Language, Record<Register, string>>;
export const EXAMPLES: { label: string; text: Localized }[] = [
  {
    label: "Charged twice",
    text: {
      en: {
        formal: "I have been charged twice and nobody has answered my emails.",
        casual: "I got charged twice and nobody's answering my emails",
      },
      fr: {
        formal: "J'ai été prélevé deux fois et personne n'a répondu à mes e-mails.",
        casual: "J'ai été débité deux fois et personne répond à mes mails",
      },
      de: {
        formal: "Mir wurde zweimal abgebucht, und niemand hat auf meine E-Mails geantwortet.",
        casual: "Mir wurde zweimal was abgebucht und keiner antwortet auf meine Mails",
      },
    },
  },
  {
    label: "Address change",
    text: {
      en: {
        formal: "Hello, I moved last month and would like to update the delivery address on my account.",
        casual: "Hi, I moved last month and need to update the delivery address on my account.",
      },
      fr: {
        formal: "Bonjour, j'ai déménagé le mois dernier et je souhaiterais mettre à jour l'adresse de livraison de mon compte.",
        casual: "Salut, j'ai déménagé le mois dernier, faut que je change l'adresse de livraison sur mon compte.",
      },
      de: {
        formal: "Guten Tag, ich bin letzten Monat umgezogen und möchte die Lieferadresse in meinem Konto ändern.",
        casual: "Hi, bin letzten Monat umgezogen und muss die Lieferadresse in meinem Konto ändern.",
      },
    },
  },
  {
    label: "Thank you",
    text: {
      en: { formal: "Thank you so much for your support!!!", casual: "Thanks so much for the help!!!" },
      fr: { formal: "Merci infiniment pour votre aide !!!", casual: "Merci trop pour ton aide !!!" },
      de: { formal: "Vielen herzlichen Dank für Ihre Unterstützung!!!", casual: "Danke dir tausendmal für die Hilfe!!!" },
    },
  },
];
// What the agent says back. The voice changes; the words are only here to have something to speak.
export const REPLIES: Record<Language, Record<Tone, string>> = {
  en: {
    frustrated: "I'm sorry about the double charge. I've flagged it for a refund, and you'll get a confirmation by email within the hour.",
    neutral: "Sure. I've updated the delivery address on your account, so your next order will ship to the new one.",
    enthusiastic: "You're very welcome! It was a pleasure to help, and we're here whenever you need us.",
  },
  fr: {
    frustrated: "Je suis désolée pour ce double prélèvement. J'ai demandé le remboursement, vous recevrez une confirmation par e-mail dans l'heure.",
    neutral: "C'est noté. J'ai mis à jour votre adresse de livraison, votre prochaine commande partira à la nouvelle adresse.",
    enthusiastic: "Avec grand plaisir ! Ce fut un plaisir de vous aider, et nous restons à votre disposition.",
  },
  de: {
    frustrated: "Das mit der doppelten Abbuchung tut mir leid. Ich habe die Erstattung veranlasst, Sie erhalten innerhalb einer Stunde eine Bestätigung.",
    neutral: "Gern. Ich habe Ihre Lieferadresse aktualisiert, Ihre nächste Bestellung geht an die neue Adresse.",
    enthusiastic: "Sehr gern geschehen! Es war mir eine Freude, und wir sind jederzeit für Sie da.",
  },
};

// Candidates only accept 100 characters of text.
export const AUDITION: Record<Language, (n: number) => string> = {
  en: (n) => `Test voice for candidate ${n}.`,
  fr: (n) => `Voix de test pour le candidat ${n}.`,
  de: (n) => `Teststimme für Kandidat ${n}.`,
};
