# Mathematical and Geometric Specification

This document details the analytical geometry implemented in [`src/scene.js`](../src/scene.js) to render non-square balanced ternary FPGA (Field-Programmable Gate Array, a digital integrated circuit with reconfigurable logic blocks and interconnects) fabrics using Three.js over WebGL (Web Graphics Library, a browser programming interface for hardware-accelerated graphics).

---

## 1. Isotropic $120^\circ$ Y-Junction Polygon

The central metallic divider of every T-CLB (Ternary Configurable Logic Block, a programmable three-state hexagonal logic tile) is extruded from a closed planar 2D (Two-Dimensional, planar coordinate space) polygon of nine exact vertices. Let $L$ denote arm length and $w = \text{armWidth} / 2$ denote half-thickness.

Each arm axis $\theta_i \in \{30^\circ, 150^\circ, 270^\circ\}$ defines a unit direction vector $\vec{u}_i$ and its counter-clockwise normal $\vec{n}_i$:

$$\vec{u}_i = (\cos \theta_i, \sin \theta_i), \quad \vec{n}_i = (-\sin \theta_i, \cos \theta_i)$$

Each flat arm tip is bounded by two vertices:

$$P_{i,\text{right}} = L\vec{u}_i - w\vec{n}_i, \quad P_{i,\text{left}} = L\vec{u}_i + w\vec{n}_i$$

Between any two adjacent arms separated by $120^\circ$, the inner corner lies along the bisector $\phi_i = \theta_i + 60^\circ \in \{90^\circ, 210^\circ, 330^\circ\}$ at radial distance:

$$r_{\text{inner}} = \frac{w}{\sin 60^\circ} = \frac{2w}{\sqrt{3}}$$

$$C_i = r_{\text{inner}} (\cos \phi_i, \sin \phi_i)$$

Traversing $(P_{0,\text{right}}, P_{0,\text{left}}, C_0, P_{1,\text{right}}, P_{1,\text{left}}, C_1, P_{2,\text{right}}, P_{2,\text{left}}, C_2)$ produces a continuous manifold shape without overlapping self-intersections, allowing clean bevel extrusion in `THREE.ExtrudeGeometry`.

---

## 2. Tripartite Rhombus Partitioning of a Pointy-Top Hexagon

A regular pointy-top hexagon of outer radius $R$ places its six vertices at angles $30^\circ, 90^\circ, 150^\circ, 210^\circ, 270^\circ, 330^\circ$. Three alternate vertices ($30^\circ, 150^\circ, 270^\circ$) align with the Y-junction arms, dividing the hexagon into three congruent rhombi with $60^\circ$ and $120^\circ$ interior angles:

| Balanced State | Angular Span | Center Angle | Physical Elevation Behavior |
| :---: | :---: | :---: | :--- |
| `0` (Neutral) | $30^\circ \to 150^\circ$ | $90^\circ$ (Top) | Elevates on state `0` |
| `-1` (Negative) | $150^\circ \to 270^\circ$ | $210^\circ$ (Left) | Elevates on state `-1` |
| `+1` (Positive) | $270^\circ \to 30^\circ$ | $330^\circ$ (Right) | Elevates on state `+1` |

To provide physical clearance around the golden Y arms, each rhombus vertex is interpolated slightly toward the rhombus centroid before extrusion. Active sectors smoothly interpolate upward along the world Y axis, pairing color encoding with 3D (Three-Dimensional, volumetric spatial geometry) physical relief. Recursive barycentric subdivision of each sector produces $3 \to 9 \to 27$ sub-cells for ternary LUT (Look-Up Table, a memory array storing multi-valued logic truth tables) layout visualization.

---

## 3. Axial and Cubic Lattice Projection

Using axial coordinates $(q, r)$ derived from zero-sum cubic coordinates $(q, r, s)$ where $s = -q - r$, cell centers project onto the horizontal $(x, z)$ plane with pitch radius $R_{\text{pitch}}$:

$$x = R_{\text{pitch}}\left(\sqrt{3}\,q + \frac{\sqrt{3}}{2}\,r\right), \quad z = R_{\text{pitch}}\left(\frac{3}{2}\,r\right)$$

In this projection, moving by $(+1, 0)$ shifts horizontally along $+X$, while $(0, +1)$ shifts $60^\circ$ toward $+Z$ (downward on screen).

---

## 4. Disjointness Proof for the 21-Cell `Word21` Cluster

A 7-cell `Tryte6` rosette centered at $(q_c, r_c)$ occupies the set of cubic offsets:

$$\mathcal{N} = \{(0,0,0), (1,0,-1), (1,-1,0), (0,-1,1), (-1,0,1), (-1,1,0), (0,1,-1)\}$$

In cubic coordinates, rotating a vector $(q, r, s)$ by $120^\circ$ corresponds to cyclic permutation:

$$R_{120^\circ}(q, r, s) = (s, q, r)$$

Choosing the first rosette center at $O_0 = (2, -1, -1)$ aligns directly along the $30^\circ$ arm direction in $(x, z)$ space:

$$x_0 = \sqrt{3}(2 - 0.5)R_{\text{pitch}} = 1.5\sqrt{3}\,R_{\text{pitch}}, \quad z_0 = -1.5\,R_{\text{pitch}}$$

Applying $R_{120^\circ}$ yields the three symmetric cluster origins:
* $O_0 = (2, -1, -1)$ along $30^\circ$
* $O_1 = (-1, -1, 2)$ along $150^\circ$
* $O_2 = (-1, 2, -1)$ along $270^\circ$

The pairwise $L_1$ cubic distance between any two cluster centers is:

$$d_{\text{hex}}(O_i, O_j) = \frac{|q_i - q_j| + |r_i - r_j| + |s_i - s_j|}{2} = \frac{3 + 3 + 0}{2} = 3$$

Because each rosette has radius $1$, a center separation of $3$ guarantees that every tile in $O_i + \mathcal{N}$ is strictly disjoint from every tile in $O_j + \mathcal{N}$ ($i \ne j$), leaving the origin cell $(0, 0, 0)$ open to house the central Y-bus connecting all three 7-cell clusters into a unified 21-trit `Word21` fabric.
