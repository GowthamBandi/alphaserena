package com.alphaserena;

import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.Parameterized;

import pl.leancode.patrol.PatrolJUnitRunner;


/**
 * Patrol's Android entry point (Patrol 4.x parameterized pattern).
 *
 * Patrol enumerates the Dart tests in integration_test/ and runs each one as a
 * separate JUnit case, so a failure names the Dart test rather than the whole
 * bundle. Nothing is asserted here — the Dart file is where the assertions are.
 *
 * NOTE: MainActivity.kt sits under a `com/example/alphaserena/` directory but
 * declares `package com.alphaserena` — Kotlin does not require the two to
 * agree. It is therefore in THIS package and needs no import.
 */
@RunWith(Parameterized.class)
public class MainActivityTest {

    @Parameterized.Parameters(name = "{0}")
    public static Object[] testCases() {
        PatrolJUnitRunner instrumentation =
                (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.setUp(MainActivity.class);
        instrumentation.waitForPatrolAppService();
        return instrumentation.listDartTests();
    }

    private final String dartTestName;

    public MainActivityTest(String dartTestName) {
        this.dartTestName = dartTestName;
    }

    @Test
    public void runDartTest() {
        PatrolJUnitRunner instrumentation =
                (PatrolJUnitRunner) InstrumentationRegistry.getInstrumentation();
        instrumentation.runDartTest(dartTestName);
    }
}
