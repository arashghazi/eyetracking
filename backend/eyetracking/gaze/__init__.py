"""Gaze estimation service: a swappable estimator behind one small HTTP surface.

Frames are processed in memory and discarded. The service reports whether its estimator is
synthetic; sessions recorded with a synthetic estimator never yield measurement claims.
"""
