## @file InputValidation.pm
# @brief Centralized security validation and escaping module for DocDB
#
# @details This module provides comprehensive input validation and sanitization
# functions to prevent XSS, SQL injection, and other security vulnerabilities.
# It includes validators for various data types including IDs, names, emails,
# dates, and text content.
#
# @author DocDB Development Team
# @date Created: September 2025 (Bug #657 response)
# @version 1.0
#
# @note All validation functions follow a consistent pattern:
# - Return validated/sanitized value on success
# - Return empty string on failure
# - Add error messages to @main::ErrorStack
#
# @see https://docdb.fnal.gov/DocDB/SecurityBestPractices

package InputValidation;

use strict;
use warnings;
use HTML::Entities;

our $VERSION = '1.0';

# ============================================================================
# LENGTH CONSTANTS - Centralized limits for all input fields
# ============================================================================

# Document and content limits
use constant MAX_TITLE_LENGTH        => 200;
use constant MAX_ABSTRACT_LENGTH     => 5000;
use constant MAX_DESCRIPTION_LENGTH  => 5000;
use constant MAX_COMMENT_LENGTH      => 1000;
use constant MAX_NOTE_LENGTH         => 2000;
use constant DEFAULT_TEXT_LENGTH     => 1000;

# User and identity limits
use constant MAX_USERNAME_LENGTH     => 50;
use constant MAX_PASSWORD_LENGTH     => 128;
use constant MAX_EMAIL_LENGTH        => 100;
use constant MAX_NAME_LENGTH         => 100;
use constant MAX_FIRSTNAME_LENGTH    => 50;
use constant MAX_MIDDLENAME_LENGTH   => 50;
use constant MAX_LASTNAME_LENGTH     => 50;

# Organization limits
use constant MAX_INSTITUTION_LENGTH  => 100;
use constant MAX_PROJECT_LENGTH      => 100;
use constant MAX_JOURNAL_LENGTH      => 100;
use constant MAX_PUBLISHER_LENGTH    => 100;

# Technical limits
use constant MAX_URL_LENGTH          => 500;
use constant MAX_FILENAME_LENGTH     => 255;
use constant MAX_PATH_LENGTH         => 1024;
use constant MAX_KEYWORD_LENGTH      => 50;
use constant MAX_ACRONYM_LENGTH      => 20;
use constant MAX_MODE_LENGTH         => 20;
use constant MAX_ACTION_LENGTH       => 20;

# Search and display limits
use constant MAX_SEARCH_LENGTH       => 200;
use constant MAX_QUERY_LENGTH        => 500;
use constant MAX_FIELD_LENGTH        => 50;

# Date/time limits
use constant MIN_YEAR               => 1900;
use constant MAX_YEAR               => 2100;

# ============================================================================
# PHASE 3: VALIDATOR STRICT MODE CONFIGURATION
# ============================================================================
# This configuration enables gradual rollout of strict validation while
# maintaining XSS protection in permissive mode.
# 0 = permissive (XSS-only validation)
# 1 = strict (full validation rules)

our %VALIDATOR_STRICT_MODE = (
    # Core validators (likely to go strict first)
    'validate_id'                      => 0,
    'validate_required'                => 0,
    'validate_required_id'             => 0,
    'validate_document_id'             => 0,
    'validate_required_document_id'    => 0,
    'validate_email'                   => 0,
    'validate_filename'                => 0,
    'validate_help_term'               => 0,
    'validate_allowlist'               => 0,
    'validate_url'                     => 0,

    # Date/time validators
    'validate_date_string'             => 0,
    'validate_year'                    => 0,
    'validate_month'                   => 0,
    'validate_day'                     => 0,
    'validate_date'                    => 0,
    'validate_time'                    => 0,

    # Array validators
    'validate_id_array'                => 0,
    'validate_text_array'              => 0,
    'validate_time_array'              => 0,
    'validate_split_param'             => 0,

    # Name and identity validators
    'validate_firstname'               => 0,
    'validate_middlename'              => 0,
    'validate_lastname'                => 0,
    'validate_name'                    => 0,
    'validate_username'                => 0,
    'validate_certificate_cn'          => 0,

    # Content validators
    'validate_title'                   => 0,
    'validate_short_description'       => 0,
    'validate_long_description'        => 0,
    'validate_abstract'                => 0,
    'validate_author_list'             => 0,
    'validate_location'                => 0,
    'validate_keywords'                => 0,
    'validate_search_text'             => 0,
    'validate_note'                    => 0,
    'validate_topic_name'              => 0,
    'validate_extension'               => 0,
    'validate_password'                => 0,
    'validate_group'                   => 0,
    'validate_no_html'                 => 0,
);

# ============================================================================
# STRICT MODE HELPER FUNCTIONS
# ============================================================================

## @fn set_validator_strict_mode($validator_name, $strict)
# @brief Enable or disable strict mode for a specific validator
# @param $validator_name Name of the validator function
# @param $strict 1 for strict mode, 0 for permissive mode
# @return Success status
sub set_validator_strict_mode {
    my ($validator_name, $strict) = @_;
    return 0 unless exists $VALIDATOR_STRICT_MODE{$validator_name};
    $VALIDATOR_STRICT_MODE{$validator_name} = $strict ? 1 : 0;
    return 1;
}

## @fn check_xss_only($value, $name)
# @brief Check for XSS without other HTML restrictions (for permissive mode)
# @param $value Value to check
# @param $name Parameter name for error messages
# @return 1 if safe, 0 if XSS detected
sub check_xss_only {
    my ($value, $name) = @_;
    $name ||= 'input';

    # Check for dangerous XSS patterns - comprehensive detection
    # Note: We need to be careful not to reject legitimate angle brackets in text like "< >" or "2 < 3"
    # Only reject patterns that look like actual HTML/XML tags with tag names
    if ($value =~ /<(?:script|img|iframe|object|embed|applet|meta|link|style|body|html|svg|base|form|input|button|select|textarea|video|audio|track|source)\b[^>]*>/i ||  # Dangerous HTML tags
        $value =~ /<\w+[^>]*\son\w+\s*=/i ||      # Any tag with event handlers (onclick, onerror, etc)
        $value =~ /javascript:\s*(?:alert|eval|prompt)/i ||  # javascript: URLs with actual XSS functions
        $value =~ /vbscript:/i ||
        $value =~ /data:\s*text\/html/i ||        # data: URIs with HTML (dangerous), but allow data:image/*
        $value =~ /on\w+\s*=\s*["']?(?:alert|eval|prompt|javascript)/i ||  # Event handlers with actual XSS
        # JavaScript injection patterns (catch common XSS payloads) - but avoid false positives
        $value =~ /<script[^>]*>|<\/script>/i ||  # Actual script tags (already caught above, but explicit)
        $value =~ /['";]\s*(?:eval|exec)\s*\(/i ||  # eval/exec after quotes (actual XSS risk)
        $value =~ /(?:document\.write|window\.location\s*=|document\.cookie)/i ||  # Actual dangerous JS patterns
        # Path traversal patterns
        $value =~ /\.\.[\/\\]/ ||                 # Directory traversal (../ or ..\)
        # SQL injection detection patterns - more context-aware
        $value =~ /['";]\s*(?:DROP|DELETE)\s+/i ||  # DROP/DELETE after quotes (actual SQL injection)
        $value =~ /;\s*(?:DROP|DELETE)\s+/i ||      # DROP/DELETE after semicolon (SQL injection)
        $value =~ /(?:OR|AND)\s+['"]?1['"]?\s*=\s*['"]?1['"]?/i ||  # 1=1 type SQL injection
        $value =~ /--\s*$/ ||                     # SQL comment at end of line (suspicious)
        $value =~ /\/\*.*DROP.*\*\//i) {          # SQL block comment with DROP (very suspicious)
        my $safe_value = _make_safe_value($value);
        push @main::ErrorStack, "Invalid $name: contains prohibited content: '$safe_value'";
        return 0;
    }
    return 1;
}

## @fn is_validator_strict($validator_name)
# @brief Check if a validator is in strict mode
# @param $validator_name Name of the validator function
# @return 1 if strict, 0 if permissive
sub is_validator_strict {
    my ($validator_name) = @_;
    return $VALIDATOR_STRICT_MODE{$validator_name} || 0;
}

## @fn get_strict_validators()
# @brief Get list of validators currently in strict mode
# @return Array of validator names in strict mode
sub get_strict_validators {
    return grep { $VALIDATOR_STRICT_MODE{$_} } keys %VALIDATOR_STRICT_MODE;
}

## @fn enable_emergency_permissive_mode()
# @brief Emergency rollback - set all validators to permissive mode
# @return Nothing
# @note Logs warning message for monitoring
sub enable_emergency_permissive_mode {
    $_ = 0 for values %VALIDATOR_STRICT_MODE;
    warn "EMERGENCY: All validators set to permissive mode";
}

## @fn set_validator_permissive($validator_name)
# @brief Set a specific validator to permissive mode
# @param $validator_name Name of the validator function
# @return Success status
# @note Logs warning for monitoring
sub set_validator_permissive {
    my ($validator_name) = @_;
    my $result = set_validator_strict_mode($validator_name, 0);
    warn "Validator $validator_name set to permissive mode" if $result;
    return $result;
}

## @defgroup EscapeFunctions Output Escaping Functions
# @{
# @brief HTML escaping functions for XSS prevention

## @fn escape_html($value)
# @brief Escapes HTML special characters to prevent XSS attacks
# @param $value The value to escape
# @return HTML-safe escaped text
# @details Escapes <, >, ", =, and ' characters.
#          Use this for all user-controlled content in HTML context.
# @note Always escape output, even if input was validated
sub escape_html {
    my ($value) = @_;
    return '' unless defined $value;

    # First escape = to prevent attribute injection (before HTML::Entities creates entities with =)
    $value =~ s/=/&#61;/g;

    # Then use HTML::Entities for other characters (exclude & to avoid double-escaping our &#61;)
    return HTML::Entities::encode($value, '<>"\'');
}

# Escape for HTML attributes
sub escape_attr {
    my ($value) = @_;
    return '' unless defined $value;
    # HTML attribute context needs quotes escaped too
    $value = HTML::Entities::encode($value, '<>&"\'');
    return $value;
}

# Escape for URLs
sub escape_url {
    my ($value) = @_;
    return '' unless defined $value;
    # URL encode for use in href attributes
    $value =~ s/([^A-Za-z0-9\-_.~])/sprintf("%%%02X", ord($1))/ge;
    return $value;
}

# Safe output with validation (combines validation + escaping)
sub safe_output {
    my ($value, $type) = @_;
    $type ||= 'text';

    return '' unless defined $value;

    # Validate based on type
    if ($type eq 'id') {
        return '' unless $value =~ /^\d+$/;
        return $value;  # IDs don't need HTML escaping
    } elsif ($type eq 'url') {
        return escape_url($value);
    } elsif ($type eq 'attr') {
        return escape_attr($value);
    } else {
        return escape_html($value);
    }
}

# Escape for hidden form fields (common vulnerability)
sub escape_hidden {
    my ($value) = @_;
    return escape_attr($value);
}

## @defgroup ValidationFunctions Input Validation Functions
# @{
# @brief Core validation functions for preventing XSS and injection attacks

## @fn validate_id($id, $name)
# @brief Validates that input is a numeric ID
# @param $id The ID value to validate
# @param $name Optional parameter name for error messages (default: 'ID')
# @return The validated ID on success, 0 on failure
# @note Adds error to @main::ErrorStack on validation failure
sub validate_id {
    my ($id, $name) = @_;
    $name ||= 'ID';

    # Don't validate undefined/empty values
    return 0 unless defined $id && length($id);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return 0 unless check_xss_only($id, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_id'}) {
        unless ($id =~ /^\d+$/) {
            my $safe_value = _make_safe_value($id);
            push @main::ErrorStack, "Invalid $name: '$safe_value'";
            return 0;
        }
    }

    return $id;
}

# Sanitize text input
sub sanitize_text {
    my ($text, $max_length) = @_;
    $max_length ||= DEFAULT_TEXT_LENGTH;  # Use constant

    return '' unless defined $text;

    # Remove null bytes
    $text =~ s/\x00//g;

    # Limit length
    $text = substr($text, 0, $max_length) if length($text) > $max_length;

    # Remove control characters (except tab, newline, carriage return)
    $text =~ s/[\x01-\x08\x0B\x0C\x0E-\x1F]//g;

    return $text;
}

# Convenience functions with predefined limits
sub sanitize_title {
    my ($text) = @_;
    return sanitize_text($text, MAX_TITLE_LENGTH);
}

sub sanitize_description {
    my ($text) = @_;
    return sanitize_text($text, MAX_DESCRIPTION_LENGTH);
}

sub sanitize_username {
    my ($text) = @_;
    return sanitize_text($text, MAX_USERNAME_LENGTH);
}

# Sanitize first name (validates and truncates to safe length)
sub sanitize_firstname {
    my ($text) = @_;
    return '' unless defined $text && $text ne '';

    # Remove control characters and limit length
    $text = sanitize_text($text, MAX_FIRSTNAME_LENGTH);

    # Additional validation for names - only allow letters, spaces, hyphens, apostrophes, and dots
    $text =~ s/[^a-zA-Z\s\-'\.]+//g;
    $text =~ s/^\s+|\s+$//g;  # Trim whitespace

    return $text;
}

# Sanitize middle name (validates and truncates to safe length)
sub sanitize_middlename {
    my ($text) = @_;
    return '' unless defined $text && $text ne '';

    # Remove control characters and limit length
    $text = sanitize_text($text, MAX_MIDDLENAME_LENGTH);

    # Additional validation for names - only allow letters, spaces, hyphens, apostrophes, and dots
    $text =~ s/[^a-zA-Z\s\-'\.]+//g;
    $text =~ s/^\s+|\s+$//g;  # Trim whitespace

    return $text;
}

# Sanitize last name (validates and truncates to safe length)
sub sanitize_lastname {
    my ($text) = @_;
    return '' unless defined $text && $text ne '';

    # Remove control characters and limit length
    $text = sanitize_text($text, MAX_LASTNAME_LENGTH);

    # Additional validation for names - only allow letters, spaces, hyphens, apostrophes, and dots
    $text =~ s/[^a-zA-Z\s\-'\.]+//g;
    $text =~ s/^\s+|\s+$//g;  # Trim whitespace

    return $text;
}

# Sanitize full name (validates and truncates to safe length)
sub sanitize_name {
    my ($text) = @_;
    return '' unless defined $text && $text ne '';

    # Remove control characters and limit length
    $text = sanitize_text($text, MAX_NAME_LENGTH);

    # Additional validation for names - only allow letters, spaces, hyphens, apostrophes, and dots
    $text =~ s/[^a-zA-Z\s\-'\.]+//g;
    $text =~ s/^\s+|\s+$//g;  # Trim whitespace

    return $text;
}

# Sanitize file extension (validates and truncates to safe length)
sub sanitize_extension {
    my ($text) = @_;
    return '' unless defined $text && $text ne '';

    # Remove leading dot if present
    $text =~ s/^\.//;

    # Only allow alphanumeric characters
    $text =~ s/[^a-zA-Z0-9]//g;

    # Limit length to reasonable extension size
    $text = substr($text, 0, 10) if length($text) > 10;

    return lc($text);  # Return lowercase
}

# Sanitize X.509 certificate Common Name (CN) according to RFC 5280
sub sanitize_certificate_cn {
    my ($text, $is_hostname) = @_;
    return '' unless defined $text && $text ne '';

    # Remove control characters and limit to 64 characters (X.509 CN limit)
    $text = sanitize_text($text, 64);

    if ($is_hostname) {
        # Hostname restrictions (CA/Browser Forum requirements)
        # Only allow: letters, numbers, hyphens, and dots
        # No spaces, underscores, or special characters
        # No non-ASCII characters (punycode should be pre-converted)
        $text =~ s/[^a-zA-Z0-9\-.]//g;

        # Additional hostname validation
        $text =~ s/^[-.]|[-.]$//g;  # Remove leading/trailing hyphens or dots
        $text =~ s/\.{2,}/./g;      # Collapse multiple dots
        $text =~ s/-{2,}/-/g;       # Collapse multiple hyphens

    } else {
        # Person name restrictions (more inclusive)
        # Allow: letters (including Unicode), numbers, spaces, and common name punctuation
        # X.509 PrintableString allows: '()+-.,/:=?
        # For names, we'll allow: spaces, hyphens, apostrophes, dots (for O'Connor, Jean-Pierre, Jr.)
        $text =~ s/[^\p{L}a-zA-Z0-9\s'\-.]//g;

        # Collapse multiple spaces and trim
        $text =~ s/\s+/ /g;
        $text =~ s/^\s+|\s+$//g;
    }

    return $text;
}

# ============================================================================
# STRICT VALIDATION FUNCTIONS - REJECT INVALID INPUT, DON'T TRANSFORM
# ============================================================================
# These functions validate input and REJECT if invalid rather than transform.
# Use these in validate_or_exit() blocks to prevent malicious input transformation.

# Validate first name (strict - rejects invalid input)
sub validate_firstname {
    my ($text, $name) = @_;
    $name ||= 'First name';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_firstname'}) {
        # Check length
        if (length($text) > MAX_FIRSTNAME_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_FIRSTNAME_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Only allow letters, spaces, hyphens, apostrophes, and dots
        if ($text !~ /^[\p{L}a-zA-Z\s'\-.\s]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: only letters, spaces, hyphens, apostrophes, and dots allowed: '$safe_value'";
            return '';
        }

        # Must not be only whitespace or special characters
        if ($text =~ /^[\s'\-.]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: must contain at least one letter: '$safe_value'";
            return '';
        }
    }

    return $text;
}

# Validate middle name (strict - rejects invalid input)
sub validate_middlename {
    my ($text, $name) = @_;
    $name ||= 'Middle name';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_middlename'}) {
        # Check length
        if (length($text) > MAX_MIDDLENAME_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_MIDDLENAME_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Only allow letters, spaces, hyphens, apostrophes, and dots
        if ($text !~ /^[\p{L}a-zA-Z\s'\-.\s]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: only letters, spaces, hyphens, apostrophes, and dots allowed: '$safe_value'";
            return '';
        }

        # Must not be only whitespace or special characters
        if ($text =~ /^[\s'\-.]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: must contain at least one letter: '$safe_value'";
            return '';
        }
    }

    return $text;
}

# Validate last name (strict - rejects invalid input)
sub validate_lastname {
    my ($text, $name) = @_;
    $name ||= 'Last name';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_lastname'}) {
        # Check length
        if (length($text) > MAX_LASTNAME_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_LASTNAME_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Only allow letters, spaces, hyphens, apostrophes, and dots
        if ($text !~ /^[\p{L}a-zA-Z\s'\-.\s]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: only letters, spaces, hyphens, apostrophes, and dots allowed: '$safe_value'";
            return '';
        }

        # Must not be only whitespace or special characters
        if ($text =~ /^[\s'\-.]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: must contain at least one letter: '$safe_value'";
            return '';
        }
    }

    return $text;
}

# Validate full name (strict - rejects invalid input)
sub validate_name {
    my ($text, $name) = @_;
    $name ||= 'Name';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_name'}) {
        # Check length
        if (length($text) > MAX_NAME_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_NAME_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Only allow letters, spaces, hyphens, apostrophes, and dots
        if ($text !~ /^[\p{L}a-zA-Z\s'\-.\s]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: only letters, spaces, hyphens, apostrophes, and dots allowed: '$safe_value'";
            return '';
        }

        # Must not be only whitespace or special characters
        if ($text =~ /^[\s'\-.]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: must contain at least one letter: '$safe_value'";
            return '';
        }
    }

    return $text;
}

# Validate username (strict - rejects invalid input)
sub validate_username {
    my ($text, $name) = @_;
    $name ||= 'Username';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_username'}) {
        # Check length
        if (length($text) > MAX_USERNAME_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_USERNAME_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Username should be alphanumeric with limited special characters
        if ($text !~ /^[a-zA-Z0-9._-]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: only letters, numbers, periods, underscores, and hyphens allowed: '$safe_value'";
            return '';
        }

        # Must start with letter or number
        if ($text !~ /^[a-zA-Z0-9]/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: must start with a letter or number: '$safe_value'";
            return '';
        }
    }

    return $text;
}

# Validate certificate CN (permissive by default, strict mode available)
sub validate_certificate_cn {
    my ($text, $is_hostname, $name) = @_;
    $name ||= 'Certificate Common Name';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_certificate_cn'}) {
        # Check length (X.509 limit)
        if (length($text) > 64) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (64 characters): '$safe_value'";
            return '';
        }

        if ($is_hostname) {
            # Hostname restrictions (CA/Browser Forum requirements)
            if ($text !~ /^[a-zA-Z0-9.-]+$/) {
                my $safe_value = _make_safe_value($text);
                push @main::ErrorStack, "Invalid $name: hostnames can only contain letters, numbers, hyphens, and dots: '$safe_value'";
                return '';
            }

            # Additional hostname validation
            if ($text =~ /^[-.]|[-.]$/) {
                my $safe_value = _make_safe_value($text);
                push @main::ErrorStack, "Invalid $name: hostname cannot start or end with hyphen or dot: '$safe_value'";
                return '';
            }

            if ($text =~ /\.{2,}|--/) {
                my $safe_value = _make_safe_value($text);
                push @main::ErrorStack, "Invalid $name: hostname cannot contain consecutive dots or hyphens: '$safe_value'";
                return '';
            }

        } else {
            # Person name restrictions (more inclusive)
            if ($text !~ /^[\p{L}a-zA-Z0-9\s'.-]+$/) {
                my $safe_value = _make_safe_value($text);
                push @main::ErrorStack, "Invalid $name: only letters, numbers, spaces, hyphens, apostrophes, and dots allowed: '$safe_value'";
                return '';
            }

            # Must contain at least one letter
            if ($text !~ /[\p{L}a-zA-Z]/) {
                my $safe_value = _make_safe_value($text);
                push @main::ErrorStack, "Invalid $name: must contain at least one letter: '$safe_value'";
                return '';
            }
        }
    }

    return $text;
}

# Validate file extension (permissive by default, strict mode available)
sub validate_extension {
    my ($text, $name) = @_;
    $name ||= 'File extension';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # Remove leading dot if present for validation
    my $ext = $text;
    $ext =~ s/^\.//;

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($ext, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_extension'}) {
        # Check length
        if (length($ext) > 10) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (10 characters): '$safe_value'";
            return '';
        }

        # Only allow alphanumeric characters
        if ($ext !~ /^[a-zA-Z0-9]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: only letters and numbers allowed: '$safe_value'";
            return '';
        }
    }

    return $ext;  # Return without leading dot
}

# Validate password (permissive by default, strict mode available)
sub validate_password {
    my ($text, $name) = @_;
    $name ||= 'Password';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode) - but don't log password content
    if ($text =~ /<[^>]*>|javascript:|data:|vbscript:|on\w+\s*=/) {
        # Don't include actual password value for security
        push @main::ErrorStack, "Invalid $name: contains prohibited content";
        return '';
    }

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_password'}) {
        # Check length
        if (length($text) > MAX_PASSWORD_LENGTH) {
            # Don't include actual password value for security
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_PASSWORD_LENGTH . " characters)";
            return '';
        }

        # Minimum length check (basic security)
        if (length($text) < 6) {
            # Don't include actual password value for security
            push @main::ErrorStack, "$name must be at least 6 characters long";
            return '';
        }

        # Check for null bytes and control characters (except tab, CR, LF)
        if ($text =~ /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/) {
            # Don't include actual password value for security
            push @main::ErrorStack, "Invalid $name: contains control characters";
            return '';
        }
    }

    # Passwords can contain most printable characters including symbols
    # We're more permissive than other validators since passwords need flexibility
    # but we still block the most dangerous patterns above

    return $text;
}

# Validate group name (permissive by default, strict mode available)
sub validate_group {
    my ($text, $name) = @_;
    $name ||= 'Group';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_group'}) {
        # Check length (use same limit as usernames)
        if (length($text) > MAX_USERNAME_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_USERNAME_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Group names should be alphanumeric with limited special characters (same as username)
        if ($text !~ /^[a-zA-Z0-9._-]+$/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: only letters, numbers, periods, underscores, and hyphens allowed: '$safe_value'";
            return '';
        }

        # Must start with letter or number
        if ($text !~ /^[a-zA-Z0-9]/) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: must start with a letter or number: '$safe_value'";
            return '';
        }
    }

    return $text;
}

sub sanitize_email_text {
    my ($text) = @_;
    return sanitize_text($text, MAX_EMAIL_LENGTH);
}

sub sanitize_url_text {
    my ($text) = @_;
    return sanitize_text($text, MAX_URL_LENGTH);
}

sub sanitize_filename_text {
    my ($text) = @_;
    return sanitize_text($text, MAX_FILENAME_LENGTH);
}

# Sanitize text with HTML escaping (prevents XSS while preserving content)
sub sanitize_and_escape_html {
    my ($text, $max_length) = @_;
    $max_length ||= DEFAULT_TEXT_LENGTH;

    return '' unless defined $text;

    # First escape HTML characters to prevent XSS
    $text = escape_html($text);

    # Then apply standard sanitization (length limits, control chars)
    $text = sanitize_text($text, $max_length);

    return $text;
}

# Validate text doesn't contain HTML/script content (strict validation)
sub validate_no_html {
    my ($text, $name) = @_;
    $name ||= 'input';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_no_html'}) {
        # In strict mode, we can add additional HTML restrictions beyond XSS
        # For now, the XSS check covers the main concerns
    }

    return $text;
}

# Validate that a value exists and passes validation
sub validate_required {
    my ($value, $validator, $name, $error_message, $error_handler, @validator_args) = @_;
    $name ||= 'parameter';

    # Special case: required validators always check for empty
    unless (defined $value && $value ne '') {
        if ($error_message) {
            push @main::ErrorStack, $error_message;
        } else {
            push @main::ErrorStack, "Required $name is missing";
        }

        # Call custom error handler if provided
        if ($error_handler && ref($error_handler) eq 'CODE') {
            $error_handler->();
        }

        return '';
    }

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($value, $name);

    # If validator is provided, use it (validator handles its own strict mode)
    if ($validator && ref($validator) eq 'CODE') {
        return $validator->($value, @validator_args);
    }

    # Otherwise just return the value if it exists
    return $value;
}

# Validate required ID parameter
sub validate_required_id {
    my ($value, $name, $error_message, $error_handler) = @_;
    $name ||= 'ID';

    # Special case: required validators always check for empty
    unless (defined $value && $value ne '') {
        if ($error_message) {
            push @main::ErrorStack, $error_message;
        } else {
            push @main::ErrorStack, "Required $name is missing";
        }

        # Call custom error handler if provided
        if ($error_handler && ref($error_handler) eq 'CODE') {
            $error_handler->();
        }

        return '';
    }

    # Delegate to validate_id which handles XSS and strict mode
    return validate_id($value, $name);
}

## @fn validate_required_document_id($value, $parameter_name, $error_message, $error_handler)
# @brief Validates required document IDs with custom error handling
# @param $value The document ID to validate
# @param $parameter_name Optional parameter name for error messages (default: 'Document ID')
# @param $error_message Optional custom error message for missing values
# @param $error_handler Optional code reference to call on error
# @return The validated document ID on success, empty string on failure
# @details Combines required field validation with document ID validation.
#          Supports both numeric and alphanumeric document IDs.
sub validate_required_document_id {
    my ($value, $parameter_name, $error_message, $error_handler) = @_;
    $parameter_name ||= 'Document ID';

    unless (defined $value && $value ne '') {
        if ($error_message) {
            push @main::ErrorStack, $error_message;
        } else {
            push @main::ErrorStack, "Required $parameter_name is missing";
        }

        # Call custom error handler if provided
        if ($error_handler && ref($error_handler) eq 'CODE') {
            $error_handler->();
        }

        return '';
    }

    return validate_document_id($value, $parameter_name);
}

# Validate date string in YYYY-MM-DD format
sub validate_date_string {
    my ($date_str) = @_;

    # Don't validate undefined/empty values
    return '' unless defined $date_str && length($date_str);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($date_str, 'Date');

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_date_string'}) {
        # Check format YYYY-MM-DD
        unless ($date_str =~ /^(\d{4})-(\d{2})-(\d{2})$/) {
            my $safe_value = _make_safe_value($date_str);
            push @main::ErrorStack, "Invalid date format (expected YYYY-MM-DD): '$safe_value'";
            return '';
        }

        my ($year, $month, $day) = ($1, $2, $3);
        return '' unless validate_date($year, $month, $day);
    }

    return $date_str;
}

# Validate individual date components
sub validate_year {
    my ($year) = @_;

    # Don't validate undefined/empty values
    return '' unless defined $year && length($year);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($year, 'Year');

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_year'}) {
        unless ($year =~ /^\d{4}$/ && $year >= MIN_YEAR && $year <= MAX_YEAR) {
            my $safe_value = _make_safe_value($year);
            push @main::ErrorStack, "Invalid year: '$safe_value'";
            return '';
        }
    }

    return $year;
}

sub validate_month {
    my ($month) = @_;

    # Don't validate undefined/empty values
    return '' unless defined $month && length($month);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($month, 'Month');

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_month'}) {
        unless ($month =~ /^\d{1,2}$/ && $month >= 1 && $month <= 12) {
            my $safe_value = _make_safe_value($month);
            push @main::ErrorStack, "Invalid month: '$safe_value'";
            return '';
        }
        return sprintf("%02d", $month);  # Return zero-padded month in strict mode
    }

    return $month;  # Return as-is in permissive mode
}

sub validate_day {
    my ($day) = @_;

    # Don't validate undefined/empty values
    return '' unless defined $day && length($day);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($day, 'Day');

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_day'}) {
        unless ($day =~ /^\d{1,2}$/ && $day >= 1 && $day <= 31) {
            my $safe_value = _make_safe_value($day);
            push @main::ErrorStack, "Invalid day: '$safe_value'";
            return '';
        }
        return sprintf("%02d", $day);  # Return zero-padded day in strict mode
    }

    return $day;  # Return as-is in permissive mode
}

# Validate date components (legacy function - kept for compatibility)
sub validate_date {
    my ($year, $month, $day) = @_;

    # Basic parameter validation
    return 0 unless defined $year && defined $month && defined $day;

    # XSS check for all parameters
    return 0 unless check_xss_only($year, 'Year');
    return 0 unless check_xss_only($month, 'Month');
    return 0 unless check_xss_only($day, 'Day');

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_date'}) {
        return 0 unless $year =~ /^\d{4}$/;
        return 0 unless $month =~ /^\d{1,2}$/;
        return 0 unless $day =~ /^\d{1,2}$/;

        return 0 if $year < MIN_YEAR || $year > MAX_YEAR;
        return 0 if $month < 1 || $month > 12;
        return 0 if $day < 1 || $day > 31;
    }

    return 1;
}

## @fn validate_allowlist($value, @allowed_values)
# @brief Validates that a value is in an allowlist of permitted values
# @param $value The value to validate
# @param @allowed_values List of allowed values
# @return The validated value on success, empty string on failure
# @details This is a general-purpose validator for enumerated values.
#          It ensures the input exactly matches one of the allowed values,
#          preventing injection attacks through parameter manipulation.
# @example
# @code
# my $mode = validate_allowlist($input, qw(add edit delete view));
# my $format = validate_allowlist($fmt, qw(HTML XML JSON));
# @endcode
sub validate_allowlist {
    my ($value, @allowed_values) = @_;

    # Don't validate undefined/empty values
    return '' unless defined $value && length($value);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($value, 'Value');

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_allowlist'}) {
        my %allowed = map { $_ => 1 } @allowed_values;
        unless ($allowed{$value}) {
            my $safe_value = _make_safe_value($value);
            push @main::ErrorStack, "Invalid value: '$safe_value'";
            return '';  # Return safe default
        }
    }

    return $value;
}

# Prevent path traversal
sub validate_filename {
    my ($filename) = @_;

    # Don't validate undefined/empty values
    return '' unless defined $filename && length($filename);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($filename, 'Filename');

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_filename'}) {
        # Reject path traversal attempts
        if ($filename =~ /\.\./ || $filename =~ /[\/\\]/) {
            my $safe_value = _make_safe_value($filename);
            push @main::ErrorStack, "Invalid filename: '$safe_value'";
            return '';
        }

        # Only allow alphanumeric, dash, underscore, dot
        unless ($filename =~ /^[A-Za-z0-9_\-\.]+$/) {
            my $safe_value = _make_safe_value($filename);
            push @main::ErrorStack, "Invalid filename characters: '$safe_value'";
            return '';
        }
    }

    return $filename;
}

## @fn validate_email($email)
# @brief Validates email address format
# @param $email The email address to validate
# @return The validated email on success, empty string on failure
# @note Uses basic RFC-compliant email regex pattern
sub validate_email {
    my ($email) = @_;

    # Don't validate undefined/empty values
    return '' unless defined $email && length($email);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($email, 'Email');

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_email'}) {
        # Basic email validation
        unless ($email =~ /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/) {
            my $safe_value = _make_safe_value($email);
            push @main::ErrorStack, "Invalid email address: '$safe_value'";
            return '';
        }
    }

    return $email;
}

# Validate URL input (permissive by default, strict mode available)
sub validate_url {
    my ($url, $name) = @_;
    $name ||= 'URL';

    # Don't validate undefined/empty values
    return '' unless defined $url && length($url);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($url, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_url'}) {
        # Check length
        if (length($url) > MAX_URL_LENGTH) {
            my $safe_value = _make_safe_value($url);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_URL_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Basic URL validation pattern
        # Allows: http, https, ftp schemes
        # Supports: domain names, IP addresses, ports, paths, query strings, fragments
        unless ($url =~ m{^
            (?:https?|ftp)://              # Protocol (http, https, or ftp)
            (?:                             # Host part
                (?:[a-zA-Z0-9\-._]+)|       # Domain name
                (?:\d{1,3}\.){3}\d{1,3}     # or IP address
            )
            (?::\d+)?                       # Optional port
            (?:/[^<>\s]*)?                  # Optional path (no spaces or angle brackets)
        $}x) {
            my $safe_value = _make_safe_value($url);
            push @main::ErrorStack, "Invalid $name format: '$safe_value'";
            return '';
        }

        # Additional security check for dangerous URI schemes
        # (redundant with check_xss_only but explicit for clarity)
        if ($url =~ /^(?:javascript|data|vbscript):/i) {
            my $safe_value = _make_safe_value($url);
            push @main::ErrorStack, "$name contains prohibited URI scheme: '$safe_value'";
            return '';
        }
    }

    return $url;
}

# Fix list context vulnerability - always return single value
sub get_single_param {
    my ($query, $param_name) = @_;

    return '' unless $query && $param_name;

    # Force scalar context to prevent list context vulnerabilities
    my $value = scalar($query->param($param_name));
    return $value || '';  # Always return single value, never list
}

## @fn validate_or_exit($query, $validation_func, $encoding, $options)
# @brief Early validation with immediate exit on failure
# @param $query CGI query object containing parameters to validate
# @param $validation_func Code reference that performs validation and returns results
# @param $encoding Optional character encoding (default: 'utf-8')
# @param $options Optional hash of dependency injection callbacks for testing
# @return Result of validation_func on success, exits on failure
# @details This is the primary security gate for DocDB scripts. It validates
#          all input parameters early in script execution and terminates with
#          a safe error page if any validation fails. This prevents malicious
#          input from reaching application logic.
# @warning This function calls exit() on validation failure
# @example
# @code
# my ($docid, $version) = InputValidation::validate_or_exit($query, sub {
#     my $id = InputValidation::get_single_param($query, 'docid');
#     $id = InputValidation::validate_document_id($id);
#     my $ver = InputValidation::get_single_param($query, 'version');
#     $ver = InputValidation::validate_id($ver) if $ver;
#     return ($id, $ver || '');
# });
# @endcode
sub validate_or_exit {
    my ($query, $validation_func, $encoding, $options) = @_;
    $encoding ||= 'utf-8';
    $options ||= {};

    # Dependency injection callbacks with sensible defaults
    my $header_func = $options->{header_func} || sub { print $query->header(-charset => $encoding); };
    my $print_func = $options->{print_func} || sub { print @_; };
    my $exit_func = $options->{exit_func} || sub { exit; };

    # Remember current error count
    my $initial_errors = scalar @main::ErrorStack;

    # Run the validation function (capture as list to preserve multiple return values)
    my @result = $validation_func->();

    # If new errors were added, exit with simple error page
    if (scalar @main::ErrorStack > $initial_errors) {
        # Log validation failures to Apache error log for debugging
        my $script_name = $ENV{SCRIPT_NAME} || 'unknown_script';
        my $remote_addr = $ENV{REMOTE_ADDR} || 'unknown_ip';
        my $request_uri = $ENV{REQUEST_URI} || 'unknown_uri';

        warn "DocDB Validation Failure: script=$script_name, ip=$remote_addr, uri=$request_uri";

        # Log each validation error (safely truncated)
        for my $i ($initial_errors .. $#main::ErrorStack) {
            my $error_msg = $main::ErrorStack[$i];
            # Safely truncate long error messages for logging
            $error_msg = substr($error_msg, 0, 200) . "..." if length($error_msg) > 200;
            warn "  Validation Error: $error_msg";
        }

        $header_func->();
        $print_func->("<html><head><title>Error</title></head><body>");
        $print_func->("<h1>Invalid Input</h1>");

        # Show the validation errors (already escaped in _make_safe_value)
        for my $i ($initial_errors .. $#main::ErrorStack) {
            $print_func->("<p>" . $main::ErrorStack[$i] . "</p>");
        }

        $print_func->("</body></html>");
        $exit_func->();
    }

    # Return the result (as list if multiple values were returned)
    return @result;
}

# ============================================================================
# ARRAY VALIDATION FUNCTIONS (Reduce boilerplate for common patterns)
# ============================================================================

# Validate time in HH:MM format
sub validate_time {
    my ($time_str) = @_;

    # Don't validate undefined/empty values
    return '' unless defined $time_str && length($time_str);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($time_str, 'Time');

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_time'}) {
        if ($time_str =~ /^(\d{1,2}):(\d{2})$/) {
            my ($hour, $min) = ($1, $2);
            if ($hour >= 0 && $hour <= 23 && $min >= 0 && $min <= 59) {
                return $time_str;
            }
        }
        my $safe_value = _make_safe_value($time_str);
        push @main::ErrorStack, "Invalid time format: '$safe_value'";
        return '';
    }

    return $time_str;
}

# Validate array of IDs (filters out invalid ones)
sub validate_id_array {
    my ($array_ref, $name, $options) = @_;
    $name ||= 'ID';
    $options ||= {};

    return [] unless $array_ref && ref($array_ref) eq 'ARRAY';

    my @valid_ids;
    for my $id (@$array_ref) {
        # Skip undefined/empty values
        next unless defined $id && length($id);

        # ALWAYS check for XSS attempts (even in permissive mode)
        unless (check_xss_only($id, $name)) {
            next;  # Skip this invalid ID
        }

        # Only apply strict validation if enabled
        if ($VALIDATOR_STRICT_MODE{'validate_id_array'}) {
            if ($id =~ /^-?\d+$/) {
                # Allow negative IDs if specified, otherwise reject them
                if ($id < 0 && !$options->{allow_negative}) {
                    my $safe_value = _make_safe_value($id);
                    push @main::ErrorStack, "Invalid $name (negative not allowed): '$safe_value'";
                } else {
                    push @valid_ids, $id;
                }
            } else {
                my $safe_value = _make_safe_value($id);
                push @main::ErrorStack, "Invalid $name: '$safe_value'";
            }
        } else {
            # Permissive mode - accept any non-XSS value
            push @valid_ids, $id;
        }
    }

    return \@valid_ids;
}

# Validate array of text (titles, notes, etc.)
sub validate_text_array {
    my ($array_ref, $max_length, $type) = @_;
    $max_length ||= DEFAULT_TEXT_LENGTH;
    $type ||= 'text';

    return [] unless $array_ref && ref($array_ref) eq 'ARRAY';

    my @valid_texts;
    for my $text (@$array_ref) {
        # Skip undefined/empty values
        next unless defined $text && length($text);

        # ALWAYS check for XSS attempts (even in permissive mode)
        unless (check_xss_only($text, $type)) {
            next;  # Skip this invalid text
        }

        # Only apply strict validation if enabled
        if ($VALIDATOR_STRICT_MODE{'validate_text_array'}) {
            if ($type eq 'title') {
                push @valid_texts, sanitize_title($text);
            } elsif ($type eq 'note') {
                push @valid_texts, sanitize_text($text, MAX_NOTE_LENGTH);
            } else {
                push @valid_texts, sanitize_text($text, $max_length);
            }
        } else {
            # Permissive mode - accept any non-XSS value
            push @valid_texts, $text;
        }
    }

    return \@valid_texts;
}

# Validate array of times
sub validate_time_array {
    my ($array_ref) = @_;

    return [] unless $array_ref && ref($array_ref) eq 'ARRAY';

    my @valid_times;
    for my $time (@$array_ref) {
        # Skip undefined/empty values
        next unless defined $time && length($time);

        # ALWAYS check for XSS attempts (even in permissive mode)
        unless (check_xss_only($time, 'time')) {
            next;  # Skip this invalid time
        }

        # Only apply strict validation if enabled
        if ($VALIDATOR_STRICT_MODE{'validate_time_array'}) {
            my $validated_time = validate_time($time);
            push @valid_times, $validated_time if $validated_time;
        } else {
            # Permissive mode - accept any non-XSS value
            push @valid_times, $time;
        }
    }

    return \@valid_times;
}

# Validate help topic keys (alphanumeric with limited special chars)
sub validate_help_term {
    my ($term) = @_;

    # Don't validate undefined/empty values
    return '' unless defined $term && length($term);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($term, 'help term');

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_help_term'}) {
        # Help terms should be alphanumeric with underscores, hyphens, dots
        # Limited length to prevent abuse
        unless ($term =~ /^[A-Za-z0-9_\-\.]{1,50}$/) {
            my $safe_value = _make_safe_value($term);
            push @main::ErrorStack, "Invalid help topic format: '$safe_value'";
            return '';
        }
    }

    return $term;
}

## @fn validate_document_id($doc_id, $parameter_name)
# @brief Validates document IDs (numeric or alphanumeric aliases)
# @param $doc_id The document ID to validate
# @param $parameter_name Optional parameter name for error messages (default: 'Document ID')
# @return The validated document ID on success, empty string on failure
# @details Accepts both numeric IDs (e.g., "12345") and alphanumeric aliases
#          (e.g., "M2627717", "LIGO-T2100123")
sub validate_document_id {
    my ($doc_id, $parameter_name) = @_;
    $parameter_name ||= 'Document ID';

    # Don't validate undefined/empty values
    return '' unless defined $doc_id && length($doc_id);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($doc_id, $parameter_name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_document_id'}) {
        # Check if it's a numeric document ID
        if ($doc_id =~ /^\d+$/) {
            return $doc_id;
        }

        # Check if it's a valid document alias (alphanumeric with hyphens)
        # Document aliases typically look like: LIGO-T2100123, M2627717
        if ($doc_id =~ /^[A-Za-z0-9\-_]{1,50}$/) {
            return $doc_id;
        }

        my $safe_value = _make_safe_value($doc_id);
        push @main::ErrorStack, "Invalid $parameter_name format: '$safe_value'";
        return '';
    }

    return $doc_id;
}

# Validate split parameters (common CGI pattern: split /\0/, $params{name})
sub validate_split_param {
    my ($param_value, $type, $options) = @_;
    $options ||= {};
    $type ||= 'text';  # Default to text if type not specified

    return [] unless defined $param_value;

    # ALWAYS check for XSS attempts in the raw parameter value
    unless (check_xss_only($param_value, 'parameter')) {
        return [];  # Return empty array if XSS detected
    }

    my @values = split /\0/, $param_value;

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_split_param'}) {
        if ($type eq 'id') {
            return validate_id_array(\@values, $options->{name} || 'ID', $options);
        } elsif ($type eq 'text') {
            return validate_text_array(\@values, $options->{max_length}, $options->{text_type});
        } elsif ($type eq 'time') {
            return validate_time_array(\@values);
        } else {
            # For unknown types, just sanitize as text
            return validate_text_array(\@values, $options->{max_length});
        }
    } else {
        # Permissive mode - still split and check each value for XSS only
        my @valid_values;
        for my $value (@values) {
            next unless defined $value && length($value);
            if (check_xss_only($value, 'parameter value')) {
                push @valid_values, $value;
            }
        }
        return \@valid_values;
    }
}

# validate_params() function removed - use individual validate_* functions in validate_or_exit() blocks instead

# Specialized validators for common content types
# These are currently wrappers for validate_no_html but can be enhanced later with specific rules

# Validate title text (strict - rejects invalid input)
sub validate_title {
    my ($text, $name) = @_;
    $name ||= 'Title';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_title'}) {
        # Check length and reject if too long
        if (length($text) > MAX_TITLE_LENGTH) {
            push @main::ErrorStack, "$name exceeds maximum length of " . MAX_TITLE_LENGTH . " characters";
            return '';
        }
    }

    return $text;
}

# Validate short description text (strict - rejects invalid input)
sub validate_short_description {
    my ($text, $name) = @_;
    $name ||= 'Short Description';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_short_description'}) {
        return validate_no_html($text, $name);
    }

    return $text;
}

# Validate long description text (permissive by default, strict mode available)
sub validate_long_description {
    my ($text, $name) = @_;
    $name ||= 'Long Description';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_long_description'}) {
        return validate_no_html($text, $name);
    }

    return $text;
}

# Validate abstract text (permissive by default, strict mode available)
sub validate_abstract {
    my ($text, $name) = @_;
    $name ||= 'Abstract';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_abstract'}) {
        return validate_no_html($text, $name);
    }

    return $text;
}

# Validate author list text (strict - rejects invalid input)
# Author lists should contain international names separated by common delimiters
sub validate_author_list {
    my ($text, $name) = @_;
    $name ||= 'Author List';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_author_list'}) {
        # Check for reasonable length
        if (length($text) > MAX_DESCRIPTION_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_DESCRIPTION_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Allow Unicode letters, numbers, spaces, and international name punctuation
        # \p{L} = any Unicode letter (supports all languages)
        # \p{N} = any Unicode number
        # \p{P} = any Unicode punctuation (includes international punctuation)
        # \p{Z} = any Unicode whitespace/separator
        # This supports names like: "José María García-López; 李明; Björn Åström; Владимир Иванов"
        if ($text !~ /^[\p{L}\p{N}\p{Z}\p{P}]+$/u) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: contains prohibited characters: '$safe_value'";
            return '';
        }

        # Remove control characters (except normal whitespace)
        $text =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
    }

    return $text;
}

# Validate location text (permissive by default, strict mode available)
# Locations can include addresses, room numbers, building names, virtual meeting URLs
sub validate_location {
    my ($text, $name) = @_;
    $name ||= 'Location';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_location'}) {
        # Check for reasonable length
        if (length($text) > MAX_DESCRIPTION_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_DESCRIPTION_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Allow Unicode letters, numbers, spaces, and location-appropriate punctuation
        # Includes: letters, numbers, spaces, common punctuation for addresses/URLs
        # Supports: "Room 123, Building A", "https://zoom.us/j/123456", "会议室 A101"
        if ($text !~ /^[\p{L}\p{N}\p{Z}\p{P}]+$/u) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: contains prohibited characters: '$safe_value'";
            return '';
        }

        # Remove control characters (except normal whitespace)
        $text =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
    }

    return $text;
}

# Validate keywords text (permissive by default, strict mode available)
# Keywords should be comma/space separated terms without HTML
sub validate_keywords {
    my ($text, $name) = @_;
    $name ||= 'Keywords';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_keywords'}) {
        # Check for reasonable length
        if (length($text) > MAX_DESCRIPTION_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_DESCRIPTION_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Allow Unicode letters, numbers, spaces, and keyword separators
        # Common separators: comma, semicolon, space, hyphen, underscore
        if ($text !~ /^[\p{L}\p{N}\s,;.\-_]+$/u) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: only letters, numbers, spaces, and common separators allowed: '$safe_value'";
            return '';
        }

        # Remove control characters (except normal whitespace)
        $text =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
    }

    return $text;
}

# Validate search text (permissive by default, strict mode available)
# Search text may include some special characters for search operators
sub validate_search_text {
    my ($text, $name) = @_;
    $name ||= 'Search Text';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_search_text'}) {
        # Check for reasonable length
        if (length($text) > 240) {  # Shorter limit for search queries
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (240 characters): '$safe_value'";
            return '';
        }

        # Allow Unicode letters, numbers, spaces, and search operators
        # Includes: quotes, wildcards, boolean operators, parentheses
        if ($text !~ /^[\p{L}\p{N}\s"'*+\-()&|!]+$/u) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: contains prohibited characters: '$safe_value'";
            return '';
        }

        # Remove control characters (except normal whitespace)
        $text =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
    }

    return $text;
}

# Validate note text (permissive by default, strict mode available)
# Notes and comments with slightly more flexible formatting than descriptions
sub validate_note {
    my ($text, $name) = @_;
    $name ||= 'Note';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_note'}) {
        # Check for reasonable length
        if (length($text) > MAX_DESCRIPTION_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_DESCRIPTION_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Allow Unicode letters, numbers, spaces, and note-appropriate punctuation
        # More permissive than other validators to allow natural note-taking
        if ($text !~ /^[\p{L}\p{N}\p{Z}\p{P}]+$/u) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: contains prohibited characters: '$safe_value'";
            return '';
        }

        # Remove control characters (except normal whitespace)
        $text =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
    }

    return $text;
}

# Validate topic name text (permissive by default, strict mode available)
# Topic names are shorter, more constrained than general descriptions
sub validate_topic_name {
    my ($text, $name) = @_;
    $name ||= 'Topic Name';

    # Don't validate undefined/empty values
    return '' unless defined $text && length($text);

    # ALWAYS check for XSS attempts (even in permissive mode)
    return '' unless check_xss_only($text, $name);

    # Only apply strict validation if enabled
    if ($VALIDATOR_STRICT_MODE{'validate_topic_name'}) {
        # Check for reasonable length (shorter than descriptions)
        if (length($text) > MAX_NAME_LENGTH) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "$name exceeds maximum length (" . MAX_NAME_LENGTH . " characters): '$safe_value'";
            return '';
        }

        # Allow Unicode letters, numbers, spaces, and basic punctuation for topic names
        # More restrictive than descriptions - topics should be concise identifiers
        if ($text !~ /^[\p{L}\p{N}\s.\-_()]+$/u) {
            my $safe_value = _make_safe_value($text);
            push @main::ErrorStack, "Invalid $name: only letters, numbers, spaces, and basic punctuation allowed: '$safe_value'";
            return '';
        }

        # Remove control characters (except normal whitespace)
        $text =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
    }

    return $text;
}

# Helper function to create safe values for error messages
sub _make_safe_value {
    my ($text) = @_;
    return '' unless defined $text;
    # Truncate long values and replace control characters
    my $safe_value = substr($text, 0, 50) . (length($text) > 50 ? "..." : "");
    $safe_value =~ s/[\x00-\x1f\x7f-\x9f]/?/g;  # Replace control chars with ?

    # CRITICAL: HTML-escape the value to prevent XSS in error messages
    # This ensures that even if dangerous content gets into error messages,
    # it cannot be executed when displayed to users
    $safe_value = escape_html($safe_value);

    return $safe_value;
}

## @}  # End of validation functions group

## @section SecurityNotes Security Implementation Notes
#
# This module implements a defense-in-depth strategy:
# 1. **Input Validation**: All input is validated against strict patterns
# 2. **Output Escaping**: All output is escaped for its context (HTML, attributes, etc.)
# 3. **Early Validation**: validate_or_exit() ensures validation happens before processing
# 4. **Fail-Safe Defaults**: Invalid input returns empty strings, not the malicious input
# 5. **Error Logging**: Validation failures are logged for security monitoring
#
# @section UsageGuidelines Usage Guidelines
# - Always use validate_or_exit() at the beginning of CGI scripts
# - Always escape output with appropriate escape_* functions
# - Use validate_allowlist() for any enumerated values
# - Use validate_document_id() for document IDs (not validate_id())
# - Never trust user input, even after validation
#
# @section MaintenanceNotes Maintenance Notes
# - Add new validators as needed for new input types
# - Update MAX_* constants if field length requirements change
# - Test all validators with malicious input patterns
# - Review Apache error logs for validation failure patterns

1;  # Required for Perl modules