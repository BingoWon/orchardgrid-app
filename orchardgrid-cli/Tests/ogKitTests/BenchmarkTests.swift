import Testing

@testable import ogKit

@Suite("BenchmarkStat aggregation")
struct BenchmarkStatTests {

  @Test("empty input collapses to zero")
  func emptyCollapses() {
    let s = BenchmarkStat.of([])
    #expect(s.min == 0 && s.median == 0 && s.p95 == 0 && s.max == 0 && s.mean == 0)
  }

  @Test("single value fills every percentile")
  func singleValue() {
    let s = BenchmarkStat.of([42])
    #expect(s.min == 42 && s.median == 42 && s.p95 == 42 && s.max == 42 && s.mean == 42)
  }

  @Test("mean, min, max are exact for a known series")
  func knownSeries() {
    let s = BenchmarkStat.of([10, 20, 30, 40, 50])
    #expect(s.min == 10)
    #expect(s.max == 50)
    #expect(s.mean == 30)
    #expect(s.median == 30)
  }

  @Test("p95 sits at or near the top for 20-element series")
  func p95OnLargeSeries() {
    let values = Array(stride(from: 1.0, through: 20.0, by: 1.0))
    let s = BenchmarkStat.of(values)
    #expect(s.p95 >= 19)
  }
}
