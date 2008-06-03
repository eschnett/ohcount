// rhtml.rl written by Mitchell Foral. mitchell<att>caladbolg<dott>net.

/************************* Required for every parser *************************/
#ifndef RAGEL_RHTML_PARSER
#define RAGEL_RHTML_PARSER

#include "ragel_parser_macros.h"

// the name of the language
const char *RHTML_LANG = "html";

// the languages entities
const char *rhtml_entities[] = {
  "space", "comment", "doctype",
  "tag", "entity", "any"
};

// constants associated with the entities
enum {
  RHTML_SPACE = 0, RHTML_COMMENT, RHTML_DOCTYPE,
  RHTML_TAG, RHTML_ENTITY, RHTML_ANY
};

/*****************************************************************************/

#include "css_parser.h"
#include "javascript_parser.h"
#include "ruby_parser.h"

%%{
  machine rhtml;
  write data;
  include common "common.rl";
  #EMBED(css)
  #EMBED(javascript)
  #EMBED(ruby)

  # Line counting machine

  action rhtml_ccallback {
    switch(entity) {
    case RHTML_SPACE:
      ls
      break;
    case RHTML_ANY:
      code
      break;
    case INTERNAL_NL:
      emb_internal_newline(RHTML_LANG)
      break;
    case NEWLINE:
      emb_newline(RHTML_LANG)
      break;
    case CHECK_BLANK_ENTRY:
      check_blank_entry(RHTML_LANG)
    }
  }

  rhtml_comment := (
    #'<!--' @comment (
      newline %{ entity = INTERNAL_NL; } %rhtml_ccallback
      |
      ws
      |
      ^(space | [\-<]) @comment
      |
      '<' '%' @{ saw(RUBY_LANG); fcall rhtml_ruby_line; }
      |
      '<' !'%'
    )* :>> '-->' @comment @{ fgoto rhtml_line; };

  rhtml_sq_str := (
    #'\'' @code (
      newline %{ entity = INTERNAL_NL; } %rhtml_ccallback
      |
      ws
      |
      [^\r\n\f\t '\\<] @code
      |
      '\\' nonnewline @code
      |
      '<' '%' @{ saw(RUBY_LANG); fcall rhtml_ruby_line; }
      |
      '<' !'%'
    )* '\'' @{ fgoto rhtml_line; };
  rhtml_dq_str := (
    #'"' @code (
      newline %{ entity = INTERNAL_NL; } %rhtml_ccallback
      |
      ws
      |
      [^\r\n\f\t "\\<] @code
      |
      '\\' nonnewline @code
      |
      '<' '%' @{ saw(RUBY_LANG); fcall rhtml_ruby_line; }
      |
      '<' !'%'
    )* '"' @{ fgoto rhtml_line; };
  #rhtml_string = rhtml_sq_str | rhtml_dq_str;

  ws_or_inl = (ws | newline @{ entity = INTERNAL_NL; } %rhtml_ccallback);

  rhtml_css_entry = '<' /style/i [^>]+ :>> 'text/css' [^>]+ '>' @code;
  rhtml_css_outry = '</' /style/i ws_or_inl* '>' @code;
  rhtml_css_line := |*
    rhtml_css_outry @{ p = ts; fgoto rhtml_line; };
    # unmodified CSS patterns
    spaces      ${ entity = CSS_SPACE; } => css_ccallback;
    css_comment;
    css_string;
    newline     ${ entity = NEWLINE;   } => css_ccallback;
    ^space      ${ entity = CSS_ANY;   } => css_ccallback;
  *|;

  rhtml_js_entry = '<' /script/i [^>]+ :>> 'text/javascript' [^>]+ '>' @code;
  rhtml_js_outry = '</' /script/i ws_or_inl* '>' @code;
  rhtml_js_line := |*
    rhtml_js_outry @{ p = ts; fgoto rhtml_line; };
    # unmodified Javascript patterns
    spaces     ${ entity = JS_SPACE; } => js_ccallback;
    js_comment;
    js_string;
    newline    ${ entity = NEWLINE;  } => js_ccallback;
    ^space     ${ entity = JS_ANY;   } => js_ccallback;
  *|;

  rhtml_ruby_entry = '<%' @code;
  rhtml_ruby_outry = '%>' @reset_seen @code;
  rhtml_ruby_line := |*
    rhtml_ruby_outry @{ p = ts; fret; };
    # unmodified Ruby patterns
    spaces        ${ entity = RUBY_SPACE; } => ruby_ccallback;
    ruby_comment;
    ruby_string;
    newline       ${ entity = NEWLINE;    } => ruby_ccallback;
    ^space        ${ entity = RUBY_ANY;   } => ruby_ccallback;
  *|;

  rhtml_line := |*
    rhtml_css_entry @{ entity = CHECK_BLANK_ENTRY; } @rhtml_ccallback
      @{ fgoto rhtml_css_line; };
    rhtml_js_entry @{ entity = CHECK_BLANK_ENTRY; } @rhtml_ccallback
      @{ fgoto rhtml_js_line; };
    rhtml_ruby_entry @{ entity = CHECK_BLANK_ENTRY; } @rhtml_ccallback
      @{ saw(RUBY_LANG); } => { fcall rhtml_ruby_line; };
    # standard RHTML patterns
    spaces       ${ entity = RHTML_SPACE; } => rhtml_ccallback;
    '<!--'       @comment                   => { fgoto rhtml_comment; };
    '\''         @code                      => { fgoto rhtml_sq_str;  };
    '"'          @code                      => { fgoto rhtml_dq_str;  };
    newline      ${ entity = NEWLINE;     } => rhtml_ccallback;
    ^space       ${ entity = RHTML_ANY;   } => rhtml_ccallback;
  *|;

  # Entity machine

  action rhtml_ecallback {
    callback(RHTML_LANG, entity, cint(ts), cint(te));
  }

  rhtml_entity := 'TODO:';
}%%

/************************* Required for every parser *************************/

/* Parses a string buffer with RHTML markup.
 *
 * @param *buffer The string to parse.
 * @param length The length of the string to parse.
 * @param count Integer flag specifying whether or not to count lines. If yes,
 *   uses the Ragel machine optimized for counting. Otherwise uses the Ragel
 *   machine optimized for returning entity positions.
 * @param *callback Callback function. If count is set, callback is called for
 *   every line of code, comment, or blank with 'lcode', 'lcomment', and
 *   'lblank' respectively. Otherwise callback is called for each entity found.
 */
void parse_rhtml(char *buffer, int length, int count,
  void (*callback) (const char *lang, const char *entity, int start, int end)
  ) {
  init

  const char *seen = 0;

  %% write init;
  cs = (count) ? rhtml_en_rhtml_line : rhtml_en_rhtml_entity;
  %% write exec;

  // if no newline at EOF; callback contents of last line
  if (count) { process_last_line(RHTML_LANG) }
}

#endif

/*****************************************************************************/
