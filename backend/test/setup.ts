// Loads .env for tests run from a developer machine. In CI the runner injects
// the same variables, and dotenv leaves anything already set alone.
import 'dotenv/config';
