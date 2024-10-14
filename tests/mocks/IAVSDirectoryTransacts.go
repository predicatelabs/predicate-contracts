// Code generated by mockery. DO NOT EDIT.

package mocks

import (
	IAVSDirectory "github.com/PredicateLabs/predicate-avs/gen/bindings/IAVSDirectory"
	bind "github.com/ethereum/go-ethereum/accounts/abi/bind"

	common "github.com/ethereum/go-ethereum/common"

	mock "github.com/stretchr/testify/mock"

	types "github.com/ethereum/go-ethereum/core/types"
)

// IAVSDirectoryTransacts is an autogenerated mock type for the IAVSDirectoryTransacts type
type IAVSDirectoryTransacts struct {
	mock.Mock
}

type IAVSDirectoryTransacts_Expecter struct {
	mock *mock.Mock
}

func (_m *IAVSDirectoryTransacts) EXPECT() *IAVSDirectoryTransacts_Expecter {
	return &IAVSDirectoryTransacts_Expecter{mock: &_m.Mock}
}

// DeregisterOperatorFromAVS provides a mock function with given fields: opts, operator
func (_m *IAVSDirectoryTransacts) DeregisterOperatorFromAVS(opts *bind.TransactOpts, operator common.Address) (*types.Transaction, error) {
	ret := _m.Called(opts, operator)

	if len(ret) == 0 {
		panic("no return value specified for DeregisterOperatorFromAVS")
	}

	var r0 *types.Transaction
	var r1 error
	if rf, ok := ret.Get(0).(func(*bind.TransactOpts, common.Address) (*types.Transaction, error)); ok {
		return rf(opts, operator)
	}
	if rf, ok := ret.Get(0).(func(*bind.TransactOpts, common.Address) *types.Transaction); ok {
		r0 = rf(opts, operator)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*types.Transaction)
		}
	}

	if rf, ok := ret.Get(1).(func(*bind.TransactOpts, common.Address) error); ok {
		r1 = rf(opts, operator)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// IAVSDirectoryTransacts_DeregisterOperatorFromAVS_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'DeregisterOperatorFromAVS'
type IAVSDirectoryTransacts_DeregisterOperatorFromAVS_Call struct {
	*mock.Call
}

// DeregisterOperatorFromAVS is a helper method to define mock.On call
//   - opts *bind.TransactOpts
//   - operator common.Address
func (_e *IAVSDirectoryTransacts_Expecter) DeregisterOperatorFromAVS(opts interface{}, operator interface{}) *IAVSDirectoryTransacts_DeregisterOperatorFromAVS_Call {
	return &IAVSDirectoryTransacts_DeregisterOperatorFromAVS_Call{Call: _e.mock.On("DeregisterOperatorFromAVS", opts, operator)}
}

func (_c *IAVSDirectoryTransacts_DeregisterOperatorFromAVS_Call) Run(run func(opts *bind.TransactOpts, operator common.Address)) *IAVSDirectoryTransacts_DeregisterOperatorFromAVS_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(*bind.TransactOpts), args[1].(common.Address))
	})
	return _c
}

func (_c *IAVSDirectoryTransacts_DeregisterOperatorFromAVS_Call) Return(_a0 *types.Transaction, _a1 error) *IAVSDirectoryTransacts_DeregisterOperatorFromAVS_Call {
	_c.Call.Return(_a0, _a1)
	return _c
}

func (_c *IAVSDirectoryTransacts_DeregisterOperatorFromAVS_Call) RunAndReturn(run func(*bind.TransactOpts, common.Address) (*types.Transaction, error)) *IAVSDirectoryTransacts_DeregisterOperatorFromAVS_Call {
	_c.Call.Return(run)
	return _c
}

// RegisterOperatorToAVS provides a mock function with given fields: opts, operator, operatorSignature
func (_m *IAVSDirectoryTransacts) RegisterOperatorToAVS(opts *bind.TransactOpts, operator common.Address, operatorSignature IAVSDirectory.ISignatureUtilsSignatureWithSaltAndExpiry) (*types.Transaction, error) {
	ret := _m.Called(opts, operator, operatorSignature)

	if len(ret) == 0 {
		panic("no return value specified for RegisterOperatorToAVS")
	}

	var r0 *types.Transaction
	var r1 error
	if rf, ok := ret.Get(0).(func(*bind.TransactOpts, common.Address, IAVSDirectory.ISignatureUtilsSignatureWithSaltAndExpiry) (*types.Transaction, error)); ok {
		return rf(opts, operator, operatorSignature)
	}
	if rf, ok := ret.Get(0).(func(*bind.TransactOpts, common.Address, IAVSDirectory.ISignatureUtilsSignatureWithSaltAndExpiry) *types.Transaction); ok {
		r0 = rf(opts, operator, operatorSignature)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*types.Transaction)
		}
	}

	if rf, ok := ret.Get(1).(func(*bind.TransactOpts, common.Address, IAVSDirectory.ISignatureUtilsSignatureWithSaltAndExpiry) error); ok {
		r1 = rf(opts, operator, operatorSignature)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// IAVSDirectoryTransacts_RegisterOperatorToAVS_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'RegisterOperatorToAVS'
type IAVSDirectoryTransacts_RegisterOperatorToAVS_Call struct {
	*mock.Call
}

// RegisterOperatorToAVS is a helper method to define mock.On call
//   - opts *bind.TransactOpts
//   - operator common.Address
//   - operatorSignature IAVSDirectory.ISignatureUtilsSignatureWithSaltAndExpiry
func (_e *IAVSDirectoryTransacts_Expecter) RegisterOperatorToAVS(opts interface{}, operator interface{}, operatorSignature interface{}) *IAVSDirectoryTransacts_RegisterOperatorToAVS_Call {
	return &IAVSDirectoryTransacts_RegisterOperatorToAVS_Call{Call: _e.mock.On("RegisterOperatorToAVS", opts, operator, operatorSignature)}
}

func (_c *IAVSDirectoryTransacts_RegisterOperatorToAVS_Call) Run(run func(opts *bind.TransactOpts, operator common.Address, operatorSignature IAVSDirectory.ISignatureUtilsSignatureWithSaltAndExpiry)) *IAVSDirectoryTransacts_RegisterOperatorToAVS_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(*bind.TransactOpts), args[1].(common.Address), args[2].(IAVSDirectory.ISignatureUtilsSignatureWithSaltAndExpiry))
	})
	return _c
}

func (_c *IAVSDirectoryTransacts_RegisterOperatorToAVS_Call) Return(_a0 *types.Transaction, _a1 error) *IAVSDirectoryTransacts_RegisterOperatorToAVS_Call {
	_c.Call.Return(_a0, _a1)
	return _c
}

func (_c *IAVSDirectoryTransacts_RegisterOperatorToAVS_Call) RunAndReturn(run func(*bind.TransactOpts, common.Address, IAVSDirectory.ISignatureUtilsSignatureWithSaltAndExpiry) (*types.Transaction, error)) *IAVSDirectoryTransacts_RegisterOperatorToAVS_Call {
	_c.Call.Return(run)
	return _c
}

// UpdateAVSMetadataURI provides a mock function with given fields: opts, metadataURI
func (_m *IAVSDirectoryTransacts) UpdateAVSMetadataURI(opts *bind.TransactOpts, metadataURI string) (*types.Transaction, error) {
	ret := _m.Called(opts, metadataURI)

	if len(ret) == 0 {
		panic("no return value specified for UpdateAVSMetadataURI")
	}

	var r0 *types.Transaction
	var r1 error
	if rf, ok := ret.Get(0).(func(*bind.TransactOpts, string) (*types.Transaction, error)); ok {
		return rf(opts, metadataURI)
	}
	if rf, ok := ret.Get(0).(func(*bind.TransactOpts, string) *types.Transaction); ok {
		r0 = rf(opts, metadataURI)
	} else {
		if ret.Get(0) != nil {
			r0 = ret.Get(0).(*types.Transaction)
		}
	}

	if rf, ok := ret.Get(1).(func(*bind.TransactOpts, string) error); ok {
		r1 = rf(opts, metadataURI)
	} else {
		r1 = ret.Error(1)
	}

	return r0, r1
}

// IAVSDirectoryTransacts_UpdateAVSMetadataURI_Call is a *mock.Call that shadows Run/Return methods with type explicit version for method 'UpdateAVSMetadataURI'
type IAVSDirectoryTransacts_UpdateAVSMetadataURI_Call struct {
	*mock.Call
}

// UpdateAVSMetadataURI is a helper method to define mock.On call
//   - opts *bind.TransactOpts
//   - metadataURI string
func (_e *IAVSDirectoryTransacts_Expecter) UpdateAVSMetadataURI(opts interface{}, metadataURI interface{}) *IAVSDirectoryTransacts_UpdateAVSMetadataURI_Call {
	return &IAVSDirectoryTransacts_UpdateAVSMetadataURI_Call{Call: _e.mock.On("UpdateAVSMetadataURI", opts, metadataURI)}
}

func (_c *IAVSDirectoryTransacts_UpdateAVSMetadataURI_Call) Run(run func(opts *bind.TransactOpts, metadataURI string)) *IAVSDirectoryTransacts_UpdateAVSMetadataURI_Call {
	_c.Call.Run(func(args mock.Arguments) {
		run(args[0].(*bind.TransactOpts), args[1].(string))
	})
	return _c
}

func (_c *IAVSDirectoryTransacts_UpdateAVSMetadataURI_Call) Return(_a0 *types.Transaction, _a1 error) *IAVSDirectoryTransacts_UpdateAVSMetadataURI_Call {
	_c.Call.Return(_a0, _a1)
	return _c
}

func (_c *IAVSDirectoryTransacts_UpdateAVSMetadataURI_Call) RunAndReturn(run func(*bind.TransactOpts, string) (*types.Transaction, error)) *IAVSDirectoryTransacts_UpdateAVSMetadataURI_Call {
	_c.Call.Return(run)
	return _c
}

// NewIAVSDirectoryTransacts creates a new instance of IAVSDirectoryTransacts. It also registers a testing interface on the mock and a cleanup function to assert the mocks expectations.
// The first argument is typically a *testing.T value.
func NewIAVSDirectoryTransacts(t interface {
	mock.TestingT
	Cleanup(func())
}) *IAVSDirectoryTransacts {
	mock := &IAVSDirectoryTransacts{}
	mock.Mock.Test(t)

	t.Cleanup(func() { mock.AssertExpectations(t) })

	return mock
}
