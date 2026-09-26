const std = @import("std");

pub const Token = struct {
    /// Byte offset where the lexeme starts in the source string.
    start: u32,

    /// Byte offset one past the end of the lexeme.
    end: u32,

    /// Classification of the token.
    tag: Tag,

    pub const Tag = enum {

        // Keywords
        keyword_import,
        keyword_struct,
        keyword_enum,
        keyword_func,
        keyword_let,
        keyword_mut,
        keyword_defer,
        keyword_return,
        keyword_break,
        keyword_continue,
        keyword_if,
        keyword_else,
        keyword_while,
        keyword_match,
        keyword_try,
        keyword_or,
        keyword_as,
        keyword_true,
        keyword_false,
        keyword_many,

        // Reserved words
        keyword_for,
        keyword_in,
        keyword_pub,
        keyword_const,
        keyword_union,
        keyword_type,

        // Special
        invalid,
        eof,

        /// Statement terminator.
        ///
        /// Both an explicit `;` and an eligible newline may
        /// eventually produce this token.
        term,

        // Names and literals
        identifier,

        number_literal,
        integer_literal,
        float_literal,
        string_literal,
        char_literal,

        // Operators
        bang, // !
        pipe, // |
        pipe_pipe, // ||
        ampersand_ampersand, // &&

        equal, // =
        equal_equal, // ==
        bang_equal, // !=

        plus, // +
        minus, // -
        asterisk, // *
        slash, // /
        percent, // %

        angle_bracket_left, // <
        angle_bracket_right, // >
        angle_bracket_left_equal, // <=
        angle_bracket_right_equal, // >=

        plus_equal, // +=
        minus_equal, // -=
        asterisk_equal, // *=
        slash_equal, // /=

        pipe_angle_bracket_right, // |>

        // Punctuation
        l_paren, // (
        r_paren, // )

        l_brace, // {
        r_brace, // }

        l_bracket, // [
        r_bracket, // ]

        comma, // ,
        colon, // :
        period, // .
        pound, // #
        question_mark, // ?

        equal_angle_bracket_right, // =>
    };

    pub const keywords = std.StaticStringMap(Token.Tag).initComptime(.{
        .{ "import", .keyword_import },
        .{ "struct", .keyword_struct },
        .{ "enum", .keyword_enum },
        .{ "func", .keyword_func },
        .{ "let", .keyword_let },
        .{ "mut", .keyword_mut },
        .{ "defer", .keyword_defer },
        .{ "return", .keyword_return },
        .{ "break", .keyword_break },
        .{ "continue", .keyword_continue },
        .{ "if", .keyword_if },
        .{ "else", .keyword_else },
        .{ "while", .keyword_while },
        .{ "match", .keyword_match },
        .{ "try", .keyword_try },
        .{ "or", .keyword_or },
        .{ "as", .keyword_as },
        .{ "true", .keyword_true },
        .{ "false", .keyword_false },
        .{ "many", .keyword_many },

        // Reserved
        .{ "for", .keyword_for },
        .{ "in", .keyword_in },
        .{ "pub", .keyword_pub },
        .{ "const", .keyword_const },
        .{ "union", .keyword_union },
        .{ "type", .keyword_type },
    });

    pub fn getKeyword(bytes: []const u8) ?Token.Tag {
        return keywords.get(bytes);
    }

    pub fn getLexeme(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: u32,

    pub fn init(buffer: [:0]const u8) Tokenizer {
        return .{ .buffer = buffer, .index = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0 };
    }
    const State = enum { start, identifier, number_literal, invalid, char_literal, string_literal };
    pub fn next(self: *Tokenizer) Token {
        var result: Token = .{ .start = self.index, .end = undefined, .tag = undefined };
        state: switch (State.start) {
            .start => switch (self.buffer[self.index]) {
                0 => {
                    if (self.index == self.buffer.len) {
                        return .{ .tag = .eof, .start = self.index, .end = self.index };
                    } else {
                        continue :state .invalid;
                    }
                },
                'a'...'z', 'A'...'Z', '_' => {
                    result.tag = .identifier;
                    continue :state .identifier;
                },
                '\n', '\t', '\r', ' ' => {
                    self.index += 1;
                    result.start = self.index;
                    continue :state .start;
                },
                '\'' => {
                    result.tag = .char_literal;
                    continue :state .char_literal;
                },
                '"' => {
                    result.tag = .string_literal;
                    continue :state .string_literal;
                },
                '0'...'9' => {
                    result.tag = .number_literal;
                    continue :state .number_literal;
                },
                '|' => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        '|' => result.tag = .pipe_pipe,
                        '>' => result.tag = .pipe_angle_bracket_right,
                        else => con
                
                }
                else => continue :state .invalid,
            },

            .invalid => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => {
                        if (self.index == self.buffer.len) {
                            return .{ .tag = .invalid, .start = self.index, .end = self.index };
                        } else {
                            continue :state .invalid;
                        }
                    },
                    '\n' => result.tag = .invalid,
                    else => continue :state .invalid,
                }
            },

            .identifier => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'Z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
                    else => {
                        const ident = self.buffer[result.start..self.index];
                        if (Token.getKeyword(ident)) |tag| {
                            result.tag = tag;
                        }
                    },
                }
            },

            .number_literal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '0'...'9' => continue :state .number_literal,
                    '\n' => self.index + 1,
                    else => continue :state .number_literal,
                }
            },
            .string_literal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => {
                        if (self.index != self.buffer.len) {
                            continue :state .invalid;
                        } else {
                            result.tag = .invalid;
                        }
                    },
                    '\n' => result.tag = .invalid,
                    '"' => self.index += 1,
                    0x01...0x09, 0x0b...0x1f, 0x7f => {
                        continue :state .invalid;
                    },
                    else => continue :state .string_literal,
                }
            },

            .char_literal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    0 => {
                        if (self.index != self.buffer.len) {
                            continue :state .invalid;
                        } else {
                            result.tag = .invalid;
                        }
                    },
                    '\n' => result.tag = .invalid,
                    '\'' => self.index += 1,
                    0x01...0x09, 0x0b...0x1f, 0x7f => {
                        continue :state .invalid;
                    },
                    else => continue :state .char_literal,
                }
            },
        }
        result.end = self.index;
        return result;
    }
};
