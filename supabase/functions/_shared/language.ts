/// The language a student wants explanations in (`profiles.answer_language`,
/// `0021_study_tools.sql`): English, Hindi or Gujarati.
///
/// Only explanations change — chat answers, summaries and answer feedback.
/// Exam questions stay in English, because the exams are.

export type Language = 'en' | 'hi' | 'gu';

/// Reads the caller's choice through their own client. Anything unreadable —
/// an older database without the column, say — is English.
// deno-lint-ignore no-explicit-any
export async function languageOf(supa: any, userId: string): Promise<Language> {
  const { data, error } = await supa
    .from('profiles')
    .select('answer_language')
    .eq('id', userId)
    .maybeSingle();
  if (error || !data) return 'en';
  const lang = data.answer_language;
  return lang === 'hi' || lang === 'gu' ? lang : 'en';
}

/// A rule to append to a system instruction. Empty for English, so the
/// English prompts are exactly what they were.
export function languageRule(lang: Language): string {
  if (lang === 'en') return '';
  const [name, script] = lang === 'hi'
    ? ['Hindi', 'Devanagari']
    : ['Gujarati', 'Gujarati'];
  return `\n\nLanguage: write everything the student reads in ${name}, in \
${script} script — even though the excerpts are in English. Keep technical \
terms, formulas, code, SQL and symbols in English, the way a ${name}-speaking \
student would say them in class; the first time you translate a key term, put \
the English term in brackets after it. Keep any fixed labels these \
instructions ask for (such as "FOLLOW-UPS:") exactly as written, in English, \
and keep JSON keys in English.`;
}
