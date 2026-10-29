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
        minus_angle_bracket_right, // ->

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
    const State = enum { start, identifier, number_literal, invalid, char_literal, string_literal, int_period, int_exponent, float, float_exponent, equal, bang, ampersand, pipe, minus, plus, asterisk, slash };
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
                '=' => {
                    result.tag = .equal;
                    continue :state .equal;
                },
                '!' => {
                    result.tag = .bang;
                    continue :state .bang;
                },
                '&' => continue :state .ampersand,
                '-' => {
                    result.tag = .minus;
                    continue :state .minus;
                },
                '|' => continue :state .pipe,
                '+' => {
                    result.tag = .plus;
                    continue :state .plus;
                },
                '*' => {
                    result.tag = .asterisk;
                    continue :state .asterisk;
                },
                '/' => {
                    result.tag = .slash;
                    continue :state .slash;
                },
                '%' => {
                    std.debug.print("{d} kirk", .{self.index});
                    self.index += 1;
                    result.tag = .percent;
                },
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
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
                    else => {
                        const ident = self.buffer[result.start..self.index];
                        if (Token.getKeyword(ident)) |tag| {
                            result.tag = tag;
                        }
                    },
                }
            },

            .number_literal => switch (self.buffer[self.index]) {
                '.' => continue :state .int_period,
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                    self.index += 1;
                    continue :state .number_literal;
                },
                'e', 'E', 'p', 'P' => {
                    continue :state .int_exponent;
                },
                else => {},
            },
            .int_exponent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '-', '+' => {
                        self.index += 1;
                        continue :state .float;
                    },
                    else => continue :state .number_literal,
                }
            },
            .int_period => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                        self.index += 1;
                        continue :state .float;
                    },
                    'e', 'E', 'p', 'P' => {
                        continue :state .float_exponent;
                    },
                    else => self.index -= 1,
                }
            },
            .float => switch (self.buffer[self.index]) {
                '_', 'a'...'d', 'f'...'o', 'q'...'z', 'A'...'D', 'F'...'O', 'Q'...'Z', '0'...'9' => {
                    self.index += 1;
                    continue :state .float;
                },
                'e', 'E', 'p', 'P' => {
                    continue :state .float_exponent;
                },
                else => {},
            },
            .float_exponent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '-', '+' => {
                        self.index += 1;
                        continue :state .float;
                    },
                    else => continue :state .float,
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
            .ampersand => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '&' => result.tag = .ampersand_ampersand,
                    else => {
                        result.tag = .invalid;
                        continue :state .invalid;
                    },
                }
            },
            .pipe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '|' => result.tag = .pipe_pipe,
                    '>' => result.tag = .pipe_angle_bracket_right,
                    else => {
                        result.tag = .invalid;
                        continue :state .invalid;
                    },
                }
            },
            .equal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => result.tag = .equal_equal,
                    else => {},
                }
            },
            .bang => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => result.tag = .bang_equal,
                    else => {},
                }
            },
            .minus => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => result.tag = .minus_equal,
                    '>' => result.tag = .minus_angle_bracket_right,
                    else => {},
                }
            },
            .plus => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => result.tag = .plus_equal,
                    else => {},
                }
            },
            .asterisk => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => result.tag = .asterisk_equal,
                    else => {},
                }
            },
            .slash => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => result.tag = .slash_equal,
                    else => {},
                }
            },
        }
        result.end = self.index;
        return result;
    }
};

test "lexer: keywords" {
    var token = Tokenizer.init("func let if then else");
    try std.testing.expectEqual(Token.Tag.keyword_func, token.next().tag);
    try std.testing.expectEqual(Token.Tag.keyword_let, token.next().tag);
    try std.testing.expectEqual(Token.Tag.keyword_if, token.next().tag);
    try std.testing.expectEqual(Token.Tag.identifier, token.next().tag);
    try std.testing.expectEqual(Token.Tag.keyword_else, token.next().tag);
}

test "lexer: operators" {
    var tok = Tokenizer.init("+ - * / % = == != < <= > -> |> && || ! | += *= -=");
    try std.testing.expectEqual(Token.Tag.plus, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.minus, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.asterisk, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.slash, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.percent, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.equal, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.equal_equal, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.bang_equal, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.angle_bracket_left, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.angle_bracket_left_equal, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.angle_bracket_right, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.minus_angle_bracket_right, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.equal_angle_bracket_right, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.pipe_angle_bracket_right, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.ampersand_ampersand, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.pipe_pipe, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.bang, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.pipe, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.asterisk_equal, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.plus_equal, tok.next().tag);
    try std.testing.expectEqual(Token.Tag.minus_equal, tok.next().tag);
}
