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
        keyword_true,
        keyword_false,
        keyword_for,
        keyword_in,

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
        underscore,

        number_literal,
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
        colon_colon, // ::
        colon_equal, // :=
        period, // .
        period_period, // ..

        pound, // #
        question_mark, // ?

        equal_angle_bracket_right, // =>
    };

    pub const keywords = std.StaticStringMap(Token.Tag).initComptime(.{
        .{ "import", .keyword_import },
        .{ "struct", .keyword_struct },
        .{ "enum", .keyword_enum },
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
        .{ "true", .keyword_true },
        .{ "false", .keyword_false },
        .{ "for", .keyword_for },
        .{ "in", .keyword_in },
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
    previous_tag: ?Token.Tag,

    pub fn init(buffer: [:0]const u8) Tokenizer {
        return .{
            .buffer = buffer,
            .index = if (std.mem.startsWith(u8, buffer, "\xEF\xBB\xBF")) 3 else 0,
            .previous_tag = null,
        };
    }

    const State = enum {
        start,
        invalid,
        identifier,
        int,
        int_exponent,
        int_period,
        float,
        float_exponent,
        string_literal,
        string_literal_backslash,
        char_literal,
        char_literal_backslash,
        line_comment,
        block_comment,
        equal,
        bang,
        ampersand,
        pipe,
        minus,
        plus,
        asterisk,
        slash,
        colon,
        period,
        angle_bracket_left,
        angle_bracket_right,
    };

    pub fn next(self: *Tokenizer) Token {
        var result: Token = .{
            .start = self.index,
            .end = undefined,
            .tag = undefined,
        };

        var comment_depth: usize = 0;
        var comment_has_newline = false;
        var comment_newline: u32 = undefined;

        state: switch (State.start) {
            .start => switch (self.buffer[self.index]) {
                0 => {
                    switch (self.index == self.buffer.len) {
                        true => return .{ .tag = .eof, .start = self.index, .end = self.index },
                        false => continue :state .invalid,
                    }
                },
                ' ', '\t', '\r' => {
                    self.index += 1;
                    result.start = self.index;
                    continue :state .start;
                },
                '\n' => {
                    const newline = self.index;
                    self.index += 1;
                    switch (canEndStatement(self.previous_tag)) {
                        true => {
                            self.previous_tag = .term;
                            return .{ .tag = .term, .start = newline, .end = newline + 1 };
                        },
                        false => {
                            result.start = self.index;
                            continue :state .start;
                        },
                    }
                },
                'a'...'z', 'A'...'Z', '_' => {
                    result.tag = .identifier;
                    continue :state .identifier;
                },
                '0'...'9' => {
                    result.tag = .number_literal;
                    self.index += 1;
                    continue :state .int;
                },
                '"' => {
                    result.tag = .string_literal;
                    self.index += 1;
                    continue :state .string_literal;
                },
                '\'' => {
                    result.tag = .char_literal;
                    self.index += 1;
                    continue :state .char_literal;
                },
                ';' => {
                    result.tag = .term;
                    self.index += 1;
                },
                '%' => {
                    result.tag = .percent;
                    self.index += 1;
                },
                '(' => {
                    result.tag = .l_paren;
                    self.index += 1;
                },
                ')' => {
                    result.tag = .r_paren;
                    self.index += 1;
                },
                '{' => {
                    result.tag = .l_brace;
                    self.index += 1;
                },
                '}' => {
                    result.tag = .r_brace;
                    self.index += 1;
                },
                '[' => {
                    result.tag = .l_bracket;
                    self.index += 1;
                },
                ']' => {
                    result.tag = .r_bracket;
                    self.index += 1;
                },
                ',' => {
                    result.tag = .comma;
                    self.index += 1;
                },
                '#' => {
                    result.tag = .pound;
                    self.index += 1;
                },
                '?' => {
                    result.tag = .question_mark;
                    self.index += 1;
                },
                '=' => continue :state .equal,
                '!' => continue :state .bang,
                '&' => continue :state .ampersand,
                '|' => continue :state .pipe,
                '-' => continue :state .minus,
                '+' => continue :state .plus,
                '*' => continue :state .asterisk,
                '/' => continue :state .slash,
                ':' => continue :state .colon,
                '.' => continue :state .period,
                '<' => continue :state .angle_bracket_left,
                '>' => continue :state .angle_bracket_right,
                else => continue :state .invalid,
            },

            .invalid => {
                result.tag = .invalid;
                self.index += 1;
            },

            .identifier => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state .identifier,
                    else => {
                        const identifier = self.buffer[result.start..self.index];
                        switch (identifier.len == 1 and identifier[0] == '_') {
                            true => result.tag = .underscore,
                            false => result.tag = Token.getKeyword(identifier) orelse .identifier,
                        }
                    },
                }
            },

            .int => switch (self.buffer[self.index]) {
                '.' => continue :state .int_period,
                '_', 'a'...'d', 'f'...'z', 'A'...'D', 'F'...'Z', '0'...'9' => {
                    self.index += 1;
                    continue :state .int;
                },
                'e', 'E' => continue :state .int_exponent,
                else => {},
            },

            .int_exponent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '-', '+' => {
                        self.index += 1;
                        continue :state .float;
                    },
                    else => continue :state .int,
                }
            },

            .int_period => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '_', 'a'...'d', 'f'...'z', 'A'...'D', 'F'...'Z', '0'...'9' => {
                        self.index += 1;
                        continue :state .float;
                    },
                    'e', 'E' => continue :state .float_exponent,
                    else => self.index -= 1,
                }
            },

            .float => switch (self.buffer[self.index]) {
                '_', 'a'...'d', 'f'...'z', 'A'...'D', 'F'...'Z', '0'...'9' => {
                    self.index += 1;
                    continue :state .float;
                },
                'e', 'E' => continue :state .float_exponent,
                else => {},
            },

            .float_exponent => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '-', '+' => self.index += 1,
                    else => {},
                }
                continue :state .float;
            },

            .string_literal => switch (self.buffer[self.index]) {
                0 => {
                    switch (self.index != self.buffer.len) {
                        true => self.index += 1,
                        false => {},
                    }
                    result.tag = .invalid;
                },
                '\n', 0x01...0x09, 0x0b...0x1f, 0x7f => result.tag = .invalid,
                '\\' => {
                    self.index += 1;
                    continue :state .string_literal_backslash;
                },
                '"' => self.index += 1,
                else => {
                    self.index += 1;
                    continue :state .string_literal;
                },
            },

            .string_literal_backslash => switch (self.buffer[self.index]) {
                0 => {
                    switch (self.index != self.buffer.len) {
                        true => self.index += 1,
                        false => {},
                    }
                    result.tag = .invalid;
                },
                '\n', 0x01...0x09, 0x0b...0x1f, 0x7f => result.tag = .invalid,
                else => {
                    self.index += 1;
                    continue :state .string_literal;
                },
            },

            .char_literal => switch (self.buffer[self.index]) {
                0 => {
                    switch (self.index != self.buffer.len) {
                        true => self.index += 1,
                        false => {},
                    }
                    result.tag = .invalid;
                },
                '\n', 0x01...0x09, 0x0b...0x1f, 0x7f => result.tag = .invalid,
                '\\' => {
                    self.index += 1;
                    continue :state .char_literal_backslash;
                },
                '\'' => self.index += 1,
                else => {
                    self.index += 1;
                    continue :state .char_literal;
                },
            },

            .char_literal_backslash => switch (self.buffer[self.index]) {
                0 => {
                    switch (self.index != self.buffer.len) {
                        true => self.index += 1,
                        false => {},
                    }
                    result.tag = .invalid;
                },
                '\n', 0x01...0x09, 0x0b...0x1f, 0x7f => result.tag = .invalid,
                else => {
                    self.index += 1;
                    continue :state .char_literal;
                },
            },

            .line_comment => switch (self.buffer[self.index]) {
                0 => switch (self.index == self.buffer.len) {
                    true => {
                        result.start = self.index;
                        continue :state .start;
                    },
                    false => {
                        self.index += 1;
                        continue :state .line_comment;
                    },
                },
                '\n' => {
                    result.start = self.index;
                    continue :state .start;
                },
                else => {
                    self.index += 1;
                    continue :state .line_comment;
                },
            },

            .block_comment => switch (self.buffer[self.index]) {
                0 => switch (self.index == self.buffer.len) {
                    true => result.tag = .invalid,
                    false => {
                        self.index += 1;
                        continue :state .block_comment;
                    },
                },
                '/' => switch (self.buffer[self.index + 1]) {
                    '*' => {
                        comment_depth += 1;
                        self.index += 2;
                        continue :state .block_comment;
                    },
                    else => {
                        self.index += 1;
                        continue :state .block_comment;
                    },
                },
                '*' => switch (self.buffer[self.index + 1]) {
                    '/' => {
                        // The lookahead keeps `self.index` on the `*` until
                        // the closing delimiter is recognized.
                        comment_depth -= 1;
                        self.index += 2;
                        switch (comment_depth) {
                            0 => switch (comment_has_newline) {
                                true => switch (canEndStatement(self.previous_tag)) {
                                    true => {
                                        // Preserve a newline inside trivia as
                                        // a statement boundary.
                                        self.previous_tag = .term;
                                        return .{ .tag = .term, .start = comment_newline, .end = comment_newline + 1 };
                                    },
                                    false => {},
                                },
                                false => {},
                            },
                            else => continue :state .block_comment,
                        }
                        // The complete comment was trivia; resume at the
                        // first byte after its closing delimiter.
                        result.start = self.index;
                        continue :state .start;
                    },
                    else => {
                        self.index += 1;
                        continue :state .block_comment;
                    },
                },
                '\n' => {
                    switch (comment_has_newline) {
                        false => {
                            comment_has_newline = true;
                            comment_newline = self.index;
                        },
                        true => {},
                    }
                    self.index += 1;
                    continue :state .block_comment;
                },
                else => {
                    self.index += 1;
                    continue :state .block_comment;
                },
            },

            .equal => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .equal_equal;
                        self.index += 1;
                    },
                    '>' => {
                        result.tag = .equal_angle_bracket_right;
                        self.index += 1;
                    },
                    else => result.tag = .equal,
                }
            },

            .bang => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .bang_equal;
                        self.index += 1;
                    },
                    else => result.tag = .bang,
                }
            },

            .ampersand => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '&' => {
                        result.tag = .ampersand_ampersand;
                        self.index += 1;
                    },
                    else => result.tag = .invalid,
                }
            },

            .pipe => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '|' => {
                        result.tag = .pipe_pipe;
                        self.index += 1;
                    },
                    '>' => {
                        result.tag = .pipe_angle_bracket_right;
                        self.index += 1;
                    },
                    else => result.tag = .pipe,
                }
            },

            .minus => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .minus_equal;
                        self.index += 1;
                    },
                    '>' => {
                        result.tag = .minus_angle_bracket_right;
                        self.index += 1;
                    },
                    else => result.tag = .minus,
                }
            },

            .plus => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .plus_equal;
                        self.index += 1;
                    },
                    else => result.tag = .plus,
                }
            },

            .asterisk => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .asterisk_equal;
                        self.index += 1;
                    },
                    else => result.tag = .asterisk,
                }
            },

            .slash => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '/' => {
                        self.index += 1;
                        continue :state .line_comment;
                    },
                    '*' => {
                        comment_depth = 1;
                        comment_has_newline = false;
                        self.index += 1;
                        continue :state .block_comment;
                    },
                    '=' => {
                        result.tag = .slash_equal;
                        self.index += 1;
                    },
                    else => result.tag = .slash,
                }
            },

            .colon => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    ':' => {
                        result.tag = .colon_colon;
                        self.index += 1;
                    },
                    '=' => {
                        result.tag = .colon_equal;
                        self.index += 1;
                    },
                    else => result.tag = .colon,
                }
            },

            .period => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '.' => {
                        result.tag = .period_period;
                        self.index += 1;
                    },
                    else => result.tag = .period,
                }
            },

            .angle_bracket_left => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .angle_bracket_left_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_left,
                }
            },

            .angle_bracket_right => {
                self.index += 1;
                switch (self.buffer[self.index]) {
                    '=' => {
                        result.tag = .angle_bracket_right_equal;
                        self.index += 1;
                    },
                    else => result.tag = .angle_bracket_right,
                }
            },
        }

        result.end = self.index;
        self.previous_tag = result.tag;
        return result;
    }

    fn canEndStatement(tag: ?Token.Tag) bool {
        const actual = tag orelse return false;
        return switch (actual) {
            .identifier,
            .number_literal,
            .string_literal,
            .char_literal,
            .keyword_true,
            .keyword_false,
            .keyword_return,
            .keyword_break,
            .keyword_continue,
            .r_paren,
            .r_bracket,
            .r_brace,
            => true,
            else => false,
        };
    }
};

const TestCase = struct {
    // Focused cases record the complete expected token sequence, including spans.
    source: [:0]const u8,
    expected: []const Token,
};

// Every focused case also verifies the EOF token after the expected sequence.
fn testTokenize(
    source: [:0]const u8,
    expected: []const Token,
) !void {
    var tokenizer = Tokenizer.init(source);

    for (expected) |want| {
        const actual = tokenizer.next();

        try std.testing.expectEqual(want.tag, actual.tag);
        try std.testing.expectEqual(want.start, actual.start);
        try std.testing.expectEqual(want.end, actual.end);
    }

    const eof = tokenizer.next();
    const end: u32 = @intCast(source.len);

    try std.testing.expectEqual(Token.Tag.eof, eof.tag);
    try std.testing.expectEqual(end, eof.start);
    try std.testing.expectEqual(end, eof.end);
}

// Invalid input must make progress without consuming the next token.
test "tokenizer: invalid bytes advance one byte at a time" {
    // The valid token after '$' must remain available to the next call.
    try testTokenize("$ let", &.{
        .{ .tag = .invalid, .start = 0, .end = 1 },
        .{ .tag = .identifier, .start = 2, .end = 5 },
    });

    try testTokenize("$", &.{
        .{ .tag = .invalid, .start = 0, .end = 1 },
    });

    try testTokenize("a\x00b", &.{
        .{ .tag = .identifier, .start = 0, .end = 1 },
        .{ .tag = .invalid, .start = 1, .end = 2 },
        .{ .tag = .identifier, .start = 2, .end = 3 },
    });
}

test "tokenizer: repeated calls reach EOF on invalid input" {
    var tok = Tokenizer.init("@@@");
    var iterations: usize = 0;
    var token = tok.next();

    while (token.tag != .eof and iterations < 8) : (iterations += 1) {
        try std.testing.expectEqual(token.start + 1, token.end);
        token = tok.next();
    }

    try std.testing.expectEqual(Token.Tag.eof, token.tag);
    try std.testing.expectEqual(@as(usize, 3), iterations);
}

// Exact recognition tests define Kō's lexical vocabulary and token spans.
test "tokenizer: Kō keywords" {
    const cases = [_]TestCase{
        .{ .source = "import", .expected = &.{.{ .tag = .keyword_import, .start = 0, .end = 6 }} },
        .{ .source = "struct", .expected = &.{.{ .tag = .keyword_struct, .start = 0, .end = 6 }} },
        .{ .source = "enum", .expected = &.{.{ .tag = .keyword_enum, .start = 0, .end = 4 }} },
        .{ .source = "defer", .expected = &.{.{ .tag = .keyword_defer, .start = 0, .end = 5 }} },
        .{ .source = "return", .expected = &.{.{ .tag = .keyword_return, .start = 0, .end = 6 }} },
        .{ .source = "break", .expected = &.{.{ .tag = .keyword_break, .start = 0, .end = 5 }} },
        .{ .source = "continue", .expected = &.{.{ .tag = .keyword_continue, .start = 0, .end = 8 }} },
        .{ .source = "if", .expected = &.{.{ .tag = .keyword_if, .start = 0, .end = 2 }} },
        .{ .source = "else", .expected = &.{.{ .tag = .keyword_else, .start = 0, .end = 4 }} },
        .{ .source = "while", .expected = &.{.{ .tag = .keyword_while, .start = 0, .end = 5 }} },
        .{ .source = "match", .expected = &.{.{ .tag = .keyword_match, .start = 0, .end = 5 }} },
        .{ .source = "try", .expected = &.{.{ .tag = .keyword_try, .start = 0, .end = 3 }} },
        .{ .source = "or", .expected = &.{.{ .tag = .keyword_or, .start = 0, .end = 2 }} },
        .{ .source = "true", .expected = &.{.{ .tag = .keyword_true, .start = 0, .end = 4 }} },
        .{ .source = "false", .expected = &.{.{ .tag = .keyword_false, .start = 0, .end = 5 }} },
        .{ .source = "for", .expected = &.{.{ .tag = .keyword_for, .start = 0, .end = 3 }} },
        .{ .source = "in", .expected = &.{.{ .tag = .keyword_in, .start = 0, .end = 2 }} },
    };

    for (cases) |case| {
        try testTokenize(case.source, case.expected);
    }
}

test "tokenizer: identifiers and keyword near misses" {
    const cases = [_]TestCase{
        .{ .source = "match", .expected = &.{.{ .tag = .keyword_match, .start = 0, .end = 5 }} },
        .{ .source = "matcher", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 7 }} },
        .{ .source = "let123", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 6 }} },
        .{ .source = "_name", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 5 }} },
        .{ .source = "name_2", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 6 }} },
        .{ .source = "imported", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 8 }} },
        .{ .source = "func", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 4 }} },
        .{ .source = "let", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 3 }} },
        .{ .source = "mut", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 3 }} },
        .{ .source = "as", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 2 }} },
        .{ .source = "many", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 4 }} },
        .{ .source = "pub", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 3 }} },
        .{ .source = "const", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 5 }} },
        .{ .source = "union", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 5 }} },
        .{ .source = "type", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 4 }} },
    };

    for (cases) |case| {
        try testTokenize(case.source, case.expected);
    }
}

test "tokenizer: underscore and literals" {
    const cases = [_]TestCase{
        .{ .source = "_", .expected = &.{.{ .tag = .underscore, .start = 0, .end = 1 }} },
        .{ .source = "_name", .expected = &.{.{ .tag = .identifier, .start = 0, .end = 5 }} },
        .{ .source = "123", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 3 }} },
        .{ .source = "1_000", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 5 }} },
        .{ .source = "0xFF", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 4 }} },
        .{ .source = "0b1010", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 6 }} },
        .{ .source = "1.25", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 4 }} },
        .{ .source = "2e-10", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 5 }} },
        .{ .source = "\"hello\\n\"", .expected = &.{.{ .tag = .string_literal, .start = 0, .end = 9 }} },
        .{ .source = "'x'", .expected = &.{.{ .tag = .char_literal, .start = 0, .end = 3 }} },
        .{ .source = "'\\n'", .expected = &.{.{ .tag = .char_literal, .start = 0, .end = 4 }} },
    };

    for (cases) |case| {
        try testTokenize(case.source, case.expected);
    }

    try testTokenize("1..count", &.{
        .{ .tag = .number_literal, .start = 0, .end = 1 },
        .{ .tag = .period_period, .start = 1, .end = 3 },
        .{ .tag = .identifier, .start = 3, .end = 8 },
    });
}

test "tokenizer: statement terminators" {
    try testTokenize("value;next", &.{
        .{ .tag = .identifier, .start = 0, .end = 5 },
        .{ .tag = .term, .start = 5, .end = 6 },
        .{ .tag = .identifier, .start = 6, .end = 10 },
    });

    try testTokenize("value\nnext", &.{
        .{ .tag = .identifier, .start = 0, .end = 5 },
        .{ .tag = .term, .start = 5, .end = 6 },
        .{ .tag = .identifier, .start = 6, .end = 10 },
    });

    try testTokenize("value +\nnext", &.{
        .{ .tag = .identifier, .start = 0, .end = 5 },
        .{ .tag = .plus, .start = 6, .end = 7 },
        .{ .tag = .identifier, .start = 8, .end = 12 },
    });

    try testTokenize("value\n\nnext", &.{
        .{ .tag = .identifier, .start = 0, .end = 5 },
        .{ .tag = .term, .start = 5, .end = 6 },
        .{ .tag = .identifier, .start = 7, .end = 11 },
    });
}

test "tokenizer: line and nested block comments" {
    try testTokenize("left/* outer /* inner */ outer */right", &.{
        .{ .tag = .identifier, .start = 0, .end = 4 },
        .{ .tag = .identifier, .start = 33, .end = 38 },
    });

    try testTokenize("value // note\nnext", &.{
        .{ .tag = .identifier, .start = 0, .end = 5 },
        .{ .tag = .term, .start = 13, .end = 14 },
        .{ .tag = .identifier, .start = 14, .end = 18 },
    });

    try testTokenize("value /* note\nmore */ next", &.{
        .{ .tag = .identifier, .start = 0, .end = 5 },
        .{ .tag = .term, .start = 13, .end = 14 },
        .{ .tag = .identifier, .start = 22, .end = 26 },
    });

    try testTokenize("/* unterminated", &.{
        .{ .tag = .invalid, .start = 0, .end = 15 },
    });
}

test "tokenizer: unterminated quoted literals are invalid" {
    try testTokenize("\"unterminated", &.{
        .{ .tag = .invalid, .start = 0, .end = 13 },
    });
    try testTokenize("'unterminated", &.{
        .{ .tag = .invalid, .start = 0, .end = 13 },
    });
}

test "tokenizer: number spelling validation is deferred" {
    const cases = [_]TestCase{
        .{ .source = "0x", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 2 }} },
        .{ .source = "0b_1", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 4 }} },
        .{ .source = "1__0", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 4 }} },
        .{ .source = "1_", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 2 }} },
        .{ .source = "2e", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 2 }} },
        .{ .source = "2e+", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 3 }} },
        .{ .source = "1.2_", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 4 }} },
        .{ .source = "123abc", .expected = &.{.{ .tag = .number_literal, .start = 0, .end = 6 }} },
    };

    for (cases) |case| {
        try testTokenize(case.source, case.expected);
    }
}

test "tokenizer: Kō operators have exact spans" {
    const cases = [_]TestCase{
        .{ .source = "!", .expected = &.{.{ .tag = .bang, .start = 0, .end = 1 }} },
        .{ .source = "!=", .expected = &.{.{ .tag = .bang_equal, .start = 0, .end = 2 }} },
        .{ .source = "|", .expected = &.{.{ .tag = .pipe, .start = 0, .end = 1 }} },
        .{ .source = "||", .expected = &.{.{ .tag = .pipe_pipe, .start = 0, .end = 2 }} },
        .{ .source = "|>", .expected = &.{.{ .tag = .pipe_angle_bracket_right, .start = 0, .end = 2 }} },
        .{ .source = "&&", .expected = &.{.{ .tag = .ampersand_ampersand, .start = 0, .end = 2 }} },
        .{ .source = "=", .expected = &.{.{ .tag = .equal, .start = 0, .end = 1 }} },
        .{ .source = "==", .expected = &.{.{ .tag = .equal_equal, .start = 0, .end = 2 }} },
        .{ .source = "=>", .expected = &.{.{ .tag = .equal_angle_bracket_right, .start = 0, .end = 2 }} },
        .{ .source = "->", .expected = &.{.{ .tag = .minus_angle_bracket_right, .start = 0, .end = 2 }} },
        .{ .source = "+", .expected = &.{.{ .tag = .plus, .start = 0, .end = 1 }} },
        .{ .source = "+=", .expected = &.{.{ .tag = .plus_equal, .start = 0, .end = 2 }} },
        .{ .source = "-", .expected = &.{.{ .tag = .minus, .start = 0, .end = 1 }} },
        .{ .source = "-=", .expected = &.{.{ .tag = .minus_equal, .start = 0, .end = 2 }} },
        .{ .source = "*=", .expected = &.{.{ .tag = .asterisk_equal, .start = 0, .end = 2 }} },
        .{ .source = "*", .expected = &.{.{ .tag = .asterisk, .start = 0, .end = 1 }} },
        .{ .source = "/=", .expected = &.{.{ .tag = .slash_equal, .start = 0, .end = 2 }} },
        .{ .source = "/", .expected = &.{.{ .tag = .slash, .start = 0, .end = 1 }} },
        .{ .source = "%", .expected = &.{.{ .tag = .percent, .start = 0, .end = 1 }} },
        .{ .source = "<", .expected = &.{.{ .tag = .angle_bracket_left, .start = 0, .end = 1 }} },
        .{ .source = "<=", .expected = &.{.{ .tag = .angle_bracket_left_equal, .start = 0, .end = 2 }} },
        .{ .source = ">", .expected = &.{.{ .tag = .angle_bracket_right, .start = 0, .end = 1 }} },
        .{ .source = ">=", .expected = &.{.{ .tag = .angle_bracket_right_equal, .start = 0, .end = 2 }} },
    };

    for (cases) |case| {
        try testTokenize(case.source, case.expected);
    }
}

test "tokenizer: Kō punctuation has exact spans" {
    const cases = [_]TestCase{
        .{ .source = "(", .expected = &.{.{ .tag = .l_paren, .start = 0, .end = 1 }} },
        .{ .source = ")", .expected = &.{.{ .tag = .r_paren, .start = 0, .end = 1 }} },
        .{ .source = "{", .expected = &.{.{ .tag = .l_brace, .start = 0, .end = 1 }} },
        .{ .source = "}", .expected = &.{.{ .tag = .r_brace, .start = 0, .end = 1 }} },
        .{ .source = "[", .expected = &.{.{ .tag = .l_bracket, .start = 0, .end = 1 }} },
        .{ .source = "]", .expected = &.{.{ .tag = .r_bracket, .start = 0, .end = 1 }} },
        .{ .source = ",", .expected = &.{.{ .tag = .comma, .start = 0, .end = 1 }} },
        .{ .source = ":", .expected = &.{.{ .tag = .colon, .start = 0, .end = 1 }} },
        .{ .source = ".", .expected = &.{.{ .tag = .period, .start = 0, .end = 1 }} },
        .{ .source = "#", .expected = &.{.{ .tag = .pound, .start = 0, .end = 1 }} },
        .{ .source = "?", .expected = &.{.{ .tag = .question_mark, .start = 0, .end = 1 }} },
    };

    for (cases) |case| {
        try testTokenize(case.source, case.expected);
    }
}

test "tokenizer: Kō declaration and range punctuation" {
    try testTokenize("::", &.{
        .{ .tag = .colon_colon, .start = 0, .end = 2 },
    });
    try testTokenize(":=", &.{
        .{ .tag = .colon_equal, .start = 0, .end = 2 },
    });
    try testTokenize("..", &.{
        .{ .tag = .period_period, .start = 0, .end = 2 },
    });
}

// Syntax-shaped streams verify boundaries; parsing their meaning comes later.
test "tokenizer: Kō-style declarations" {
    try testTokenize("Person::struct{}", &.{
        .{ .tag = .identifier, .start = 0, .end = 6 },
        .{ .tag = .colon_colon, .start = 6, .end = 8 },
        .{ .tag = .keyword_struct, .start = 8, .end = 14 },
        .{ .tag = .l_brace, .start = 14, .end = 15 },
        .{ .tag = .r_brace, .start = 15, .end = 16 },
    });

    try testTokenize("value:=other", &.{
        .{ .tag = .identifier, .start = 0, .end = 5 },
        .{ .tag = .colon_equal, .start = 5, .end = 7 },
        .{ .tag = .identifier, .start = 7, .end = 12 },
    });

    try testTokenize("parse_row::(line:[]u8)->Row", &.{
        .{ .tag = .identifier, .start = 0, .end = 9 },
        .{ .tag = .colon_colon, .start = 9, .end = 11 },
        .{ .tag = .l_paren, .start = 11, .end = 12 },
        .{ .tag = .identifier, .start = 12, .end = 16 },
        .{ .tag = .colon, .start = 16, .end = 17 },
        .{ .tag = .l_bracket, .start = 17, .end = 18 },
        .{ .tag = .r_bracket, .start = 18, .end = 19 },
        .{ .tag = .identifier, .start = 19, .end = 21 },
        .{ .tag = .r_paren, .start = 21, .end = 22 },
        .{ .tag = .minus_angle_bracket_right, .start = 22, .end = 24 },
        .{ .tag = .identifier, .start = 24, .end = 27 },
    });

    try testTokenize("0..count-1", &.{
        .{ .tag = .number_literal, .start = 0, .end = 1 },
        .{ .tag = .period_period, .start = 1, .end = 3 },
        .{ .tag = .identifier, .start = 3, .end = 8 },
        .{ .tag = .minus, .start = 8, .end = 9 },
        .{ .tag = .number_literal, .start = 9, .end = 10 },
    });
}

test "tokenizer: Kō loops and conditional capture" {
    try testTokenize("for item in items", &.{
        .{ .tag = .keyword_for, .start = 0, .end = 3 },
        .{ .tag = .identifier, .start = 4, .end = 8 },
        .{ .tag = .keyword_in, .start = 9, .end = 11 },
        .{ .tag = .identifier, .start = 12, .end = 17 },
    });

    try testTokenize("for i in 0..items", &.{
        .{ .tag = .keyword_for, .start = 0, .end = 3 },
        .{ .tag = .identifier, .start = 4, .end = 5 },
        .{ .tag = .keyword_in, .start = 6, .end = 8 },
        .{ .tag = .number_literal, .start = 9, .end = 10 },
        .{ .tag = .period_period, .start = 10, .end = 12 },
        .{ .tag = .identifier, .start = 12, .end = 17 },
    });

    try testTokenize("if find(id)|user|{}", &.{
        .{ .tag = .keyword_if, .start = 0, .end = 2 },
        .{ .tag = .identifier, .start = 3, .end = 7 },
        .{ .tag = .l_paren, .start = 7, .end = 8 },
        .{ .tag = .identifier, .start = 8, .end = 10 },
        .{ .tag = .r_paren, .start = 10, .end = 11 },
        .{ .tag = .pipe, .start = 11, .end = 12 },
        .{ .tag = .identifier, .start = 12, .end = 16 },
        .{ .tag = .pipe, .start = 16, .end = 17 },
        .{ .tag = .l_brace, .start = 17, .end = 18 },
        .{ .tag = .r_brace, .start = 18, .end = 19 },
    });
}

test "tokenizer: Kō example program contains no invalid tokens" {
    const source = @embedFile("alternative-example.ko");
    var tokenizer = Tokenizer.init(source);

    while (true) {
        const token = tokenizer.next();
        try std.testing.expect(token.tag != .invalid);
        if (token.tag == .eof) break;
    }
}

test "tokenizer: empty whitespace and adjacent tokens" {
    try testTokenize("", &.{});
    try testTokenize(" \t\r\n ", &.{});
    try testTokenize("(foo)+=bar", &.{
        .{ .tag = .l_paren, .start = 0, .end = 1 },
        .{ .tag = .identifier, .start = 1, .end = 4 },
        .{ .tag = .r_paren, .start = 4, .end = 5 },
        .{ .tag = .plus_equal, .start = 5, .end = 7 },
        .{ .tag = .identifier, .start = 7, .end = 10 },
    });
    try testTokenize("a|||>b", &.{
        .{ .tag = .identifier, .start = 0, .end = 1 },
        .{ .tag = .pipe_pipe, .start = 1, .end = 3 },
        .{ .tag = .pipe_angle_bracket_right, .start = 3, .end = 5 },
        .{ .tag = .identifier, .start = 5, .end = 6 },
    });
}

fn expectProgress(source: [:0]const u8) !void {
    // Broad-input tests check termination and span invariants, not token names.
    var tokenizer = Tokenizer.init(source);
    var previous_end: u32 = 0;
    var calls: usize = 0;
    const max_calls = source.len + 1;

    while (calls < max_calls) : (calls += 1) {
        const token = tokenizer.next();
        try std.testing.expect(token.start >= previous_end);
        try std.testing.expect(token.end >= token.start);
        try std.testing.expect(token.end <= source.len);

        if (token.tag == .eof) {
            try std.testing.expectEqual(@as(u32, @intCast(source.len)), token.start);
            try std.testing.expectEqual(token.start, token.end);
            return;
        }

        try std.testing.expect(token.end > token.start);
        previous_end = token.end;
    }

    try std.testing.expect(false);
}

// Broad-input tests protect termination, bounds, and monotonic progress.
test "tokenizer: every single byte terminates" {
    // Every byte must either produce a bounded token or reach EOF safely.
    var value: u16 = 0;
    while (value <= 0xff) : (value += 1) {
        var source: [1:0]u8 = .{@intCast(value)};
        try expectProgress(source[0..]);
    }
}

test "tokenizer: short generated inputs terminate" {
    // This alphabet covers sentinels, controls, identifier bytes, and operators.
    const alphabet = [_]u8{ 0x00, 0x01, 0x7f, 0x80, 0xff, ' ', '\n', 'a', 'Z', '_', '0', '!', '|', '&', '=', '+', '-', '*', '/', '%', '<', '>' };
    var source: [3:0]u8 = .{ 0, 0, 0 };

    try expectProgress(source[0..0 :0]);
    for (alphabet) |a| {
        source[0] = a;
        source[1] = 0;
        try expectProgress(source[0..1 :0]);
        for (alphabet) |b| {
            source[1] = b;
            source[2] = 0;
            try expectProgress(source[0..2 :0]);
            for (alphabet) |c| {
                source[2] = c;
                try expectProgress(source[0..3 :0]);
            }
        }
    }
}
