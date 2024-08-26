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

//include unit test files in this module in this ifdef
//Keep this sorted alphabetically

#ifdef UNIT_TESTS
#include "atmos\test_ventcrawl.dm"
#include "games\test_cards.dm"
#include "jobs\test_job_globals.dm"
#include "aicard_icons.dm"
#include "announcements.dm"
#include "areas_apcs.dm"
#include "component_tests.dm"
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
#endif
