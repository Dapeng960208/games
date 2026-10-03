"""Verify exact regenerated B05 native sources without granting runtime acceptance."""
from hashlib import sha256
import json
from pathlib import Path
import unittest
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'assets/generated/enemies/b05_regenerated_poses_v1'


class RegeneratedPoseSources(unittest.TestCase):
    def test_native_pose_registration(self):
        manifest = json.loads((ART / 'manifest.json').read_text())
        self.assertFalse(manifest['upscaled'])
        self.assertEqual(manifest['asset_family'], 'storybook_2_5d_v1')
        hashes = set()
        for identity, bank in manifest['identities'].items():
            self.assertGreater(bank['reference_body_height_px'], 0)
            self.assertEqual(set(bank['frames']), {'idle', 'telegraph', 'execute'})
            for pose, frame in bank['frames'].items():
                with self.subTest(identity=identity, pose=pose):
                    path = ART / frame['texture']
                    digest = sha256(path.read_bytes()).hexdigest()
                    self.assertEqual(digest, frame['sha256'])
                    self.assertNotIn(digest, hashes)
                    hashes.add(digest)
                    self.assertTrue((ART / frame['prompt']).read_text().strip())
                    self.assertEqual(sha256((ART / frame['prompt']).read_bytes()).hexdigest(), frame['prompt_sha256'])
                    self.assertTrue(frame.get('source_generated_file') or frame.get('library_file_id'))
                    with Image.open(path) as image:
                        self.assertEqual(image.mode, 'RGBA')
                        self.assertEqual(image.size, (frame['width'], frame['height']))
                        self.assertEqual(image.size, (1254, 1254))
                        self.assertEqual(frame['region'], [0, 0, *image.size])
                        alpha = image.getchannel('A')
                        self.assertEqual(alpha.getextrema(), (0, 255))
                        box = alpha.point(lambda value: 255 if value >= 16 else 0).getbbox()
                        self.assertEqual(list(box), frame['visible_bbox_alpha16'])
                        margins = [box[0], box[1], image.width-box[2], image.height-box[3]]
                        self.assertEqual(margins, frame['source_margin_alpha16_px'])
                        self.assertGreater(min(margins), 0, 'No meaningful source subject may clip an edge')
                        for anchor in ['foot', 'core_anchor', 'visual_outlet']:
                            x, y = frame[anchor]
                            self.assertTrue(0 <= x < image.width and 0 <= y < image.height)
                        contacts = frame.get('foot_contacts', [])
                        if contacts:
                            for axis in range(2):
                                self.assertAlmostEqual(frame['foot'][axis], sum(p[axis] for p in contacts)/len(contacts), delta=0.001)
                        self.assertTrue(frame['source_review'])


if __name__ == '__main__':
    unittest.main()
