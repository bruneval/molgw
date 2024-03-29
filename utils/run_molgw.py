#!/usr/bin/python3
##################################################
#
# This file is part of MOLGW
# Author: Fabien Bruneval
#
# This python script prepares a series of MOLGW input files
# for all the XYZ files found in directory named 'structures'
# 
#
##################################################
  

import os, sys, shutil, stat, subprocess
import collections
import molgw




##################################################
#
# Hard-coded information
#
directory       = 'run_001'
executable      = '/home/bruneval/devel/molgw-devel/molgw'
run_it          = False   # run it on the fly from python script or wait 
atom_number_max = 999     # limit the size of the calculated molecules
folder_naming   = ['basis','scf','postscf','auxil_basis']

##################################################
#
# Create the calculation list here
#
ip = []
for basis in ['aug-cc-pVDZ','aug-cc-pVTZ']:
    ipp = collections.OrderedDict()
    ipp['basis']                   = basis
    ipp['scf']                     = 'BHLYP'
    ipp['postscf']                 = 'GW'
    ipp['selfenergy_state_range']  = 3
    ipp['frozencore']              = 'yes'
    ipp['auxil_basis']             = basis + '-RI'
    ip.append(ipp)

#########################################
# Implement a size limit
#
#molecule_list = [ filexyz.replace('.xyz','') for filexyz in os.listdir("structures") ]

molecule_list = []
for filexyz in os.listdir("structures"):
    with open('structures/'+filexyz) as f:
        if int(f.readline()) <= atom_number_max:
            molecule_list.append(filexyz.replace('.xyz',''))



# Molecule list
print('=========== Molecule list')
print(molecule_list)
print('==========================')


#########################################
#
#
os.makedirs(directory,exist_ok=True)
 
script = open('run.sh','w')

for molecule in molecule_list:
    for calc in ip:

        folder_name = molecule 
        for key, value in calc.items():
            if key in folder_naming:
                folder_name = folder_name + '_' + str(value).lower()
        folder = directory + '/' + folder_name
        os.makedirs(folder,exist_ok=True)
  
        #
        # Check if the molgw.yaml is already there and finalized
        #
        yamlfilename= folder + '/molgw.yaml'
        valid_yamlfile = True

        if os.path.exists(yamlfilename):
            try:
                with open(yamlfilename, 'r') as f:
                    last_line = f.readlines()[-1]
                    if '...' not in last_line:
                        print('yaml file not terminated')
                        valid_yamlfile = False
            except:
                valid_yamlfile = False
                pass
            try:
                with open(yamlfilename, 'r') as f:
                    for line in f:
                        if 'NaN' in line:
                            print('yaml file contains some NaN')
                            valid_yamlfile = False
                            break
            except:
                valid_yamlfile = False
                pass
        else:
            print('no yaml file found')
            valid_yamlfile = False

        if valid_yamlfile:
            print('{:24} {:5} is already calculated. Skip it'.format(molecule,calc['basis']))
            continue
            
        print('{:24} {:5} to be calculated'.format(molecule,calc['basis']))
  
        os.chdir(folder)
  
        script.write('cd ' + folder + '\n')
        
        calc["comment"]  = molecule

        # Two possible techniques to input the geometry
        if False:
            fxyz = open('../../structures/' + molecule + '.xyz',"r")
            natom = int( fxyz.readline() )
            calc["natom"] = natom
            fxyz.readline()
            string = fxyz.read()
            fxyz.close()
            calc["xyz"] = string
        else:
            calc["xyz_file"] = '../../structures/' + molecule + '.xyz'

        molgw.print_input_file(calc,'molgw.in')

  
        script.write(executable + ' molgw.in > molgw.out\n')
        if run_it:
            process = subprocess.Popen([executable,'molgw.in'],stdout=subprocess.PIPE)
            output, error = process.communicate()
  
        script.write('cd ../.. \n')
  
        os.chdir('../../')

script.close()
os.chmod('run.sh',stat.S_IRUSR+stat.S_IWUSR+stat.S_IXUSR)


