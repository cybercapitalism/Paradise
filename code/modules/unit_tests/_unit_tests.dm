//include unit test files in this module in this ifdef
//Keep this sorted alphabetically

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// For advanced cases, fail unconditionally but don't return (so a test can return multiple results)
#define TEST_FAIL(reason) (Fail(reason || "No reason"))

/// Asserts that a condition is true
/// If the condition is not true, fails the test
#define TEST_ASSERT(assertion, reason) if (!(assertion)) { return Fail("Assertion failed: [reason || "No reason"]") }

/// Asserts that a parameter is not null
#define TEST_ASSERT_NOTNULL(a, reason) if (isnull(a)) { return Fail("Expected non-null value: [reason || "No reason"]") }

/// Asserts that a parameter is null
#define TEST_ASSERT_NULL(a, reason) if (!isnull(a)) { return Fail("Expected null value but received [a]: [reason || "No reason"]") }

/// Asserts that the two parameters passed are equal, fails otherwise
/// Optionally allows an additional message in the case of a failure
#define TEST_ASSERT_EQUAL(a, b, message) do { \
	var/lhs = ##a; \
	var/rhs = ##b; \
	if (lhs != rhs) { \
		return Fail("Expected [isnull(lhs) ? "null" : lhs] to be equal to [isnull(rhs) ? "null" : rhs].[message ? " [message]" : ""]"); \
	} \
} while (FALSE)

/// Asserts that the two parameters passed are not equal, fails otherwise
/// Optionally allows an additional message in the case of a failure
#define TEST_ASSERT_NOTEQUAL(a, b, message) do { \
	var/lhs = ##a; \
	var/rhs = ##b; \
	if (lhs == rhs) { \
		return Fail("Expected [isnull(lhs) ? "null" : lhs] to not be equal to [isnull(rhs) ? "null" : rhs].[message ? " [message]" : ""]"); \
	} \
} while (FALSE)

/// Constants indicating unit test completion status
#define UNIT_TEST_PASSED 0
#define UNIT_TEST_FAILED 1
#define UNIT_TEST_SKIPPED 2

#define TEST_PRE 0
#define TEST_DEFAULT 1
/// After most test steps, used for tests that run long so shorter issues can be noticed faster
#define TEST_LONGER 10
/// This must be the one of last tests to run due to the inherent nature of the test iterating every single tangible atom in the game and qdeleting all of them (while taking long sleeps to make sure the garbage collector fires properly) taking a large amount of time.
#define TEST_CREATE_AND_DESTROY 9001
/**
 * For tests that rely on create and destroy having iterated through every (tangible) atom so they don't have to do something similar.
 * Keep in mind tho that create and destroy will absolutely break the test platform, anything that relies on its shape cannot come after it.
 */
#define TEST_AFTER_CREATE_AND_DESTROY INFINITY // CHUGAFIX that element list unit test

#include "atmos\test_ventcrawl.dm"
#include "games\test_cards.dm"
#include "jobs\test_job_globals.dm"
#include "aicard_icons.dm"
#include "announcements.dm"
#include "areas_apcs.dm"
#include "component_tests.dm"

// This unit test creates and qdels almost every atom in the code, checking for errors with initialization and harddels on deletion.
// It is disabled by default for now due to the large amount of consistent errors it produces. Run the "dm: find hard deletes" task to enable it.
#ifdef REFERENCE_TRACKING_FAST
#include "create_and_destroy.dm"
#endif

#include "config_sanity.dm"
#include "crafting_lists.dm"
#include "create_and_destroy.dm"
#include "element_tests.dm"
#include "emotes.dm"
#include "init_sanity.dm"
#include "log_format.dm"
#include "map_templates.dm"
#include "map_tests.dm"
#include "origin_tech.dm"
#include "purchase_reference_test.dm"
#include "reagent_id_typos.dm"
#include "rustg_version.dm"
#include "spawn_humans.dm"
#include "spell_targeting_test.dm"
#include "sql.dm"
#include "subsystem_init.dm"
#include "subsystem_metric_sanity.dm"
#include "test_runner.dm"
#include "timer_sanity.dm"
#include "unit_test.dm"

#ifdef REFERENCE_TRACKING_DEBUG //Don't try and parse this file if ref tracking isn't turned on. IE: don't parse ref tracking please mr linter
#include "find_reference_sanity.dm"
#endif

#undef TEST_ASSERT
#undef TEST_ASSERT_EQUAL
#undef TEST_ASSERT_NOTEQUAL

#endif
