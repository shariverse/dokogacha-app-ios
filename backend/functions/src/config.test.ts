import { FUNCTIONS_REGION } from "./config";

describe("FUNCTIONS_REGION", () => {
  it("東京（asia-northeast1）に配置する", () => {
    expect(FUNCTIONS_REGION).toBe("asia-northeast1");
  });
});
