import assert from "node:assert/strict";
import test from "node:test";
import { loginCredentialsSchema } from "../dist/index.js";

test("login accepts an existing non-empty password without applying signup policy", () => {
  const result = loginCredentialsSchema.safeParse({
    email: "USER@EXAMPLE.COM",
    password: "existing",
  });

  assert.equal(result.success, true);
  assert.equal(result.data.email, "user@example.com");
});

test("login rejects an empty password", () => {
  const result = loginCredentialsSchema.safeParse({
    email: "user@example.com",
    password: "",
  });

  assert.equal(result.success, false);
});
