
"""
 Author:      Colin Pearse
 Name:        linked_list.py.t
 Description: testing linked_list.py
"""

import io
import sys
import unittest
import linked_list

lltest1 = [0,1,2,3,4,5,6,7,8,9]
lltest2 = range(0,2**16)
lltest3 = range(0,2**20)
lltest4 = range(0,2**32)

# put this test in TestLL class:
#   self.assertEqual(OLD_output_m_in_arr(2, lltest4), '4294967294\n')
def OLD_output_m_in_arr(m, arr):
    capturedOutput = io.StringIO()
    sys.stdout = capturedOutput
    linked_list.m_in_arr(m, arr)
    sys.stdout = sys.__stdout__
    return capturedOutput.getvalue()

class TestLL(unittest.TestCase):
    def test_m_in_arr(self):
        self.assertEqual(linked_list.m_in_arr(2, lltest1), 8)
        self.assertEqual(linked_list.m_in_arr(3, lltest1), 7)
        self.assertEqual(linked_list.m_in_arr(4, lltest1), 6)
        self.assertEqual(linked_list.m_in_arr(1, lltest2), 65535)
        self.assertEqual(linked_list.m_in_arr(6, lltest2), 65530)
        self.assertEqual(linked_list.OLD_m_in_arr(2, lltest3), 1048574)
        self.assertEqual(linked_list.OLD_m_in_arr(1, lltest4), 4294967295)
        #self.assertEqual(linked_list.m_in_arr(2, lltest4), 4294967294)

if __name__ == '__main__':
    unittest.main()
