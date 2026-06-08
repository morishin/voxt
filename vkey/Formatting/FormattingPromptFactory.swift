//
//  FormattingPromptFactory.swift
//  vkey
//
//  整形用の system instructions を組み立てる。言語非依存テンプレートを基本とし、
//  「入力と同じ言語で出力し、決して翻訳しない」「忠実な整文」を厳格に指示する。
//

import Foundation

enum FormattingPromptFactory {

    /// 指定モード・locale 向けの整形 instructions を返す。
    /// raw モードはモデルを使わない想定なので呼ばれない。
    nonisolated static func instructions(mode: FormattingMode, locale: Locale) -> String {
        let common = """
        You are a voice-input post-processing engine. You receive a raw speech-to-text \
        transcript and return a cleaned-up version of the SAME text.

        Strict rules:
        - Output ONLY the cleaned text. No preamble, no explanation, no quotes.
        - Keep the original language of the input. NEVER translate.
        - Do NOT summarize. Do NOT add, remove, or change information or meaning.
        - Do NOT turn the text into bullet points or lists unless the speaker clearly dictated them.
        - Preserve technical terms and proper nouns as spoken.
        """

        let modeRules: String
        switch mode {
        case .raw:
            // 通常呼ばれないが、安全のため最小整形に倒す。
            modeRules = "- Return the text essentially unchanged."
        case .light:
            modeRules = """
            - Remove filler words (e.g. um, uh, like, "えー", "あの", "その").
            - Add natural punctuation.
            - Fix only obvious self-corrections and stutters.
            - Keep the wording close to the original spoken form.
            """
        case .standard:
            modeRules = """
            - Remove filler words and unnatural repetitions.
            - Add natural punctuation.
            - Convert spoken-style phrasing into natural written language.
            - Apply natural word choices appropriate to the language, without changing meaning.
            """
        }

        return common + "\n" + modeRules
    }
}
